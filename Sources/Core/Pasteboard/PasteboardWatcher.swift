// SPDX-License-Identifier: MIT
import AppKit
import CryptoKit
import Dispatch
import os
import Synchronization

/// A captured pasteboard event ready for ingestion. Lightweight; the heavy payload bytes
/// are referenced rather than copied repeatedly.
public struct PasteboardCapture: Sendable {
    public let typeIdentifier: String
    public let payload: Data
    public let payloadString: String?
    public let frontmostBundleID: String?
    public let timestamp: Date
    public let contentHash: String
    /// True when the pasteboard contains `com.apple.is-remote-clipboard`, indicating the item
    /// arrived via Universal Clipboard (iPhone, iPad, or other Apple device).
    public let isRemote: Bool
    /// True for a copy the app marked as concealed that was kept because the person allowed that app. It is stored
    /// hidden (shown only on request) and removed when that allowance ends (ADR 0004).
    public let isConcealed: Bool
    /// When the allowance that let a concealed copy in ends (`distantFuture` for "until Pesto quits"); nil otherwise.
    public let concealedUntil: Date?
    /// For a still picture a browser copied: the address of the GIF it came from, read from the HTML flavour. The
    /// browser puts only the first frame on the pasteboard; this is where the whole GIF can be fetched (ADR 0005).
    public let sourceImageURL: URL?
    /// Formatted flavours (RTF, RTFD, HTML) captured alongside a text copy so formatting survives a normal paste.
    public let richPayload: RichTextPayload?

    /// The Mac app that made the copy. A Universal Clipboard copy comes from another device, so whichever Mac app is in
    /// front says nothing about it.
    public var sourceBundleID: String? {
        isRemote ? nil : frontmostBundleID
    }

    public static let remoteSourceName = "Another device"

    public init(
        typeIdentifier: String,
        payload: Data,
        payloadString: String? = nil,
        frontmostBundleID: String? = nil,
        timestamp: Date = .now,
        contentHash: String,
        isRemote: Bool = false,
        isConcealed: Bool = false,
        concealedUntil: Date? = nil,
        sourceImageURL: URL? = nil,
        richPayload: RichTextPayload? = nil
    ) {
        self.concealedUntil = concealedUntil
        self.sourceImageURL = sourceImageURL
        self.richPayload = richPayload
        self.typeIdentifier = typeIdentifier
        self.payload = payload
        self.payloadString = payloadString
        self.frontmostBundleID = frontmostBundleID
        self.timestamp = timestamp
        self.contentHash = contentHash
        self.isRemote = isRemote
        self.isConcealed = isConcealed
    }

    public func with(timestamp: Date) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: typeIdentifier,
            payload: payload,
            payloadString: payloadString,
            frontmostBundleID: frontmostBundleID,
            timestamp: timestamp,
            contentHash: contentHash,
            isRemote: isRemote,
            isConcealed: isConcealed,
            concealedUntil: concealedUntil,
            sourceImageURL: sourceImageURL,
            richPayload: richPayload
        )
    }
}

/// Minimal workspace protocol — `NSWorkspace.frontmostApplication` access.
/// `frontmostBundleID()` is async because `NSWorkspace` is main-actor-isolated
/// in Swift 6 strict mode. The watcher (an actor) awaits this on each tick.
public protocol FrontmostAppProviding: Sendable {
    func frontmostBundleID() async -> String?
    /// Apps that were frontmost within the last `interval` seconds. The poll can run after the user has
    /// already switched away from the app that made the copy.
    func recentBundleIDs(within interval: TimeInterval) async -> [String]
    func recentBundleIDs(within interval: TimeInterval, currentChangeCount: Int?) async -> [String]
}

public extension FrontmostAppProviding {
    func recentBundleIDs(within _: TimeInterval) async -> [String] {
        []
    }

    func recentBundleIDs(within interval: TimeInterval, currentChangeCount _: Int?) async -> [String] {
        await recentBundleIDs(within: interval)
    }
}

public final class SystemFrontmostAppProvider: FrontmostAppProviding {
    private let history = FrontmostHistory()
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    public convenience init() {
        self.init(pasteboard: AppPasteboard.reader)
    }

    public init(pasteboard: any PasteboardReading) {
        history.record(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, changeCount: pasteboard.changeCount)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [history] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            history.record(app?.bundleIdentifier, changeCount: pasteboard.changeCount)
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    public func frontmostBundleID() async -> String? {
        await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    }

    public func recentBundleIDs(within interval: TimeInterval) async -> [String] {
        history.bundleIDs(within: interval)
    }

    public func recentBundleIDs(within interval: TimeInterval, currentChangeCount: Int?) async -> [String] {
        history.bundleIDs(within: interval, currentChangeCount: currentChangeCount)
    }
}

/// The pasteboard watcher. See ADR 0006 for cadence rationale.
///
/// The watcher does NOT own storage; it produces `PasteboardCapture` values via a closure
/// (set with `onCapture(_:)`) which the storage layer is expected to drain on its own actor.
public actor PasteboardWatcher {
    /// The change count the last tick judged, readable from the timer's queue so a tick is started only for a board
    /// that has moved (P-05). The tick itself still decides what to do: a deferred or overlapping one leaves this
    /// behind the board, so the next timer fire starts it again.
    private final class ChangeMark: Sendable {
        private let count: Atomic<Int>

        init(_ count: Int) {
            self.count = Atomic(count)
        }

        var value: Int {
            count.load(ordering: .acquiring)
        }

        func set(_ count: Int) {
            self.count.store(count, ordering: .releasing)
        }
    }

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "PasteboardWatcher")

    private let pasteboard: any PasteboardReading
    private let frontmostProvider: any FrontmostAppProviding
    private var exclusionRules: ExclusionRules

    private var lastChangeCount: Int
    private let judged: ChangeMark
    private(set) var ticksStarted = 0
    private var timer: (any DispatchSourceTimer)?
    private let queue = DispatchQueue(label: "\(AppIdentity.bundleID).PasteboardWatcher", qos: .userInitiated)

    private var captureHandler: (@Sendable (PasteboardCapture) async -> Void)?
    private var blockedHandler: (@Sendable (ExclusionRules.BlockReason) -> Void)?

    /// Longer than one poll period plus scheduling slack.
    private static let recentSourceWindow: TimeInterval = 0.75

    private let ownWrites: OwnWriteGate
    private let inputIdleSeconds: @Sendable () -> TimeInterval

    /// When true, `tick()` skips all captures. The timer keeps running so we maintain an
    /// accurate `lastChangeCount` — this prevents a burst of events when the user resumes.
    public private(set) var isPaused = false

    public init(
        pasteboard: any PasteboardReading = AppPasteboard.reader,
        frontmostProvider: any FrontmostAppProviding = SystemFrontmostAppProvider(),
        exclusionRules: ExclusionRules = ExclusionRules(),
        ownWrites: OwnWriteGate = OwnWriteGate(),
        inputIdleSeconds: @escaping @Sendable () -> TimeInterval = PollPolicy.systemSecondsSinceInput
    ) {
        self.inputIdleSeconds = inputIdleSeconds
        self.ownWrites = ownWrites
        self.pasteboard = pasteboard
        self.frontmostProvider = frontmostProvider
        self.exclusionRules = exclusionRules
        self.lastChangeCount = pasteboard.changeCount
        self.judged = ChangeMark(pasteboard.changeCount)
    }

    /// Replaces the active exclusion rules. Takes effect on the next `tick()`.
    /// Call this whenever the user adds or removes entries in Settings → Privacy → App Exclusions.
    public func updateExclusionRules(_ rules: ExclusionRules) {
        exclusionRules = rules
    }

    public func pause() {
        isPaused = true
        Self.logger.info("PasteboardWatcher: paused")
    }

    public func resume() {
        // Sync lastChangeCount to current so events that occurred while paused are not re-fired
        // on the first tick after resume. (The timer may not have fired during pause in tests.)
        lastChangeCount = pasteboard.changeCount
        judged.set(lastChangeCount)
        isPaused = false
        Self.logger.info("PasteboardWatcher: resumed")
    }

    public func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    /// Told, without any content, when a copy is dropped because of its source or a concealed marker.
    public func onBlocked(_ handler: @escaping @Sendable (ExclusionRules.BlockReason) -> Void) {
        blockedHandler = handler
    }

    public func onCapture(_ handler: @escaping @Sendable (PasteboardCapture) async -> Void) {
        self.captureHandler = handler
    }

    /// Starts looking. `adaptive` lets `PollPolicy` choose the period from how recently the person used the keyboard or
    /// mouse (the app); otherwise `period` is kept (tests, and the idle CPU budget).
    public func start(period: Duration = .milliseconds(200), adaptive: Bool = false) {
        stop()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + period.timeInterval, repeating: period.timeInterval)
        let current = PollPeriod(period)
        let idleSeconds = inputIdleSeconds
        let board = pasteboard
        let judged = judged
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if board.changeCount != judged.value { Task { await self.tick() } }
            guard adaptive else { return }
            let wanted = PollPolicy.period(secondsSinceInput: idleSeconds())
            if current.change(to: wanted) {
                source.schedule(deadline: .now() + wanted.timeInterval, repeating: wanted.timeInterval)
            }
        }
        timer = source
        source.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// The timer starts a `tick()` every 200 ms whether or not the last one has finished, and a copy can spend seconds
    /// in
    /// the handler (a screenshot being read). A tick that finds one running returns: the copy it would have taken is
    /// still on the pasteboard, and the next tick after the handler finishes takes it, in order.
    private var isTicking = false

    /// True from a copy this watcher dropped (excluded app, concealed marker, remote copy with the setting off) until
    /// the next copy it captures: what the clipboard holds then is not in the history.
    public private(set) var boardHoldsUnrecordedCopy = false

    private func isIgnored(changeCount current: Int) -> Bool {
        if isPaused {
            Self.logger.debug("PasteboardWatcher: skipping capture (paused)")
            return true
        }
        if ownWrites.isOwn(changeCount: current) {
            Self.logger.debug("Ignored Pesto's own pasteboard write")
            return true
        }
        return false
    }

    public func tick() async {
        guard !isTicking else { return }
        isTicking = true
        defer { isTicking = false }
        ticksStarted += 1
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        // A write in flight is left unrecorded so its final state is judged as a whole on a later tick.
        guard !ownWrites.isWriting else { return }
        lastChangeCount = current
        judged.set(current)
        let ticking = PerfSignposts.copy.begin("watcherTick")
        defer { ticking.end() }

        if isIgnored(changeCount: current) { return }

        // Everything is read before the first suspension: a write that lands while awaiting must not be
        // judged by the types of the copy before it.
        let types = pasteboard.types()
        let isRemote = types.contains(NSPasteboard.PasteboardType("com.apple.is-remote-clipboard"))
        let typeIdentifiers = types.map(\.rawValue)
        if isRemote, dropsRemoteCopy(typeIdentifiers: typeIdentifiers) { return }
        guard let selection = readSelection(for: types, isRemote: isRemote) else { return }
        let bundleID = await frontmostProvider.frontmostBundleID()
        let recentSources = await frontmostProvider.recentBundleIDs(
            within: Self.recentSourceWindow, currentChangeCount: current
        )
        guard pasteboard.changeCount == current else {
            Self.logger.debug("Dropped pasteboard event (pasteboard changed while reading; the next tick re-reads)")
            return
        }
        let sources: [String?] = isRemote ? [] : [bundleID] + recentSources.map(Optional.some)
        if let reason = exclusionRules.blockReason(
            typeIdentifiers: typeIdentifiers, sources: sources, isRemote: isRemote
        ) {
            Self.logger.debug("Dropped pasteboard event (excluded source or concealed marker)")
            recordDrop(reason)
            return
        }
        let concealedUntil = exclusionRules.concealedKeepEnd(typeIdentifiers: typeIdentifiers, sources: sources)

        guard let resolvedSelection = await flattenSelectionIfNeeded(selection) else { return }
        let hash = (
            resolvedSelection.payload.isEmpty
                ? Data((resolvedSelection.sourceImageURL?.absoluteString ?? "").utf8)
                : resolvedSelection.payload
        ).sha256Hex
        let capture = PasteboardCapture(
            typeIdentifier: resolvedSelection.type.rawValue,
            payload: resolvedSelection.payload,
            payloadString: resolvedSelection.string,
            frontmostBundleID: bundleID,
            contentHash: hash,
            isRemote: isRemote,
            isConcealed: concealedUntil != nil, concealedUntil: concealedUntil,
            sourceImageURL: resolvedSelection.sourceImageURL,
            richPayload: resolvedSelection.richPayload
        )

        boardHoldsUnrecordedCopy = false
        if let handler = captureHandler {
            await handler(capture)
        }
    }

    private func flattenSelectionIfNeeded(_ selection: Selection) async -> Selection? {
        guard let rich = selection.richText else { return selection }
        guard let plain = await RichTextFlattener.plainText(from: rich.data, type: rich.type) else { return nil }
        return Selection(
            type: .string,
            payload: Data(plain.utf8),
            string: plain,
            richPayload: selection.richPayload
        )
    }

    private func recordDrop(_ reason: ExclusionRules.BlockReason) {
        boardHoldsUnrecordedCopy = true
        blockedHandler?(reason)
    }

    /// A remote copy is judged by its markers alone, so a dropped one is never read: reading a Universal Clipboard
    /// item starts the transfer from the other device.
    private func dropsRemoteCopy(typeIdentifiers: [String]) -> Bool {
        let reason = exclusionRules.blockReason(typeIdentifiers: typeIdentifiers, sources: [], isRemote: true)
        guard let reason else { return false }
        Self.logger.notice("Dropped a copy from another device (\(reason.rawValue, privacy: .public))")
        recordDrop(reason)
        return true
    }

    private func readSelection(for types: [NSPasteboard.PasteboardType], isRemote: Bool) -> Selection? {
        let selection = Self.selection(for: types, on: pasteboard, isRemote: isRemote)
        if selection == nil, isRemote {
            if types.contains(.fileURL) {
                Self.logger
                    .notice(
                        "A file from another device was not kept: not a picture, or macOS did not let Pesto read it"
                    )
                recordDrop(.remoteCopy)
            } else {
                Self.logger.notice("A copy from another device arrived but its data could not be read")
            }
        }
        return selection
    }

    private struct Selection {
        let type: NSPasteboard.PasteboardType
        let payload: Data
        let string: String?
        /// A copy that is only rich text: its bytes are read now and flattened later, on the main actor.
        var richText: (type: NSPasteboard.PasteboardType, data: Data)?
        var sourceImageURL: URL?
        var richPayload: RichTextPayload?
    }

    /// Rich text is flattened to its plain string for classification, masking and search, while its formatted
    /// flavours (`public.rtf`, `com.apple.flat-rtfd`, `public.html`) are kept alongside for normal paste.
    private static func selection(
        for types: [NSPasteboard.PasteboardType], on pasteboard: any PasteboardReading, isRemote: Bool
    )
    -> Selection? {
        guard let detected = PasteboardTypeDetector.detect(types: types) else {
            return htmlSelection(for: types, on: pasteboard)
        }
        if detected == .fileURL, isRemote { return remotePictureSelection(on: pasteboard) }
        if detected == .fileURL {
            let urls = pasteboard.fileURLs()
            if urls.count > 1 {
                let text = FileClip.encode(urls)
                return Selection(type: .fileURL, payload: Data(text.utf8), string: text)
            }
        }
        guard detected == .rtf || detected == .rtfd else {
            guard let payload = pasteboard.data(forType: detected), !payload.isEmpty else {
                return htmlSelection(for: types, on: pasteboard)
            }
            // The system gives no length before a read, so the one read of a flavour is the most a board can cost; what
            // follows (a decode, the rich flavours) is skipped for a copy the size limit refuses, which ingest does
            // with its message.
            if ClipSizePolicy.isTooLarge(byteCount: payload.count, typeIdentifier: detected.rawValue) {
                return Selection(type: detected, payload: payload, string: nil)
            }
            let isText = detected == .string || detected == .URL || detected == .fileURL
            let rich = detected == .string ? richFlavors(for: types, on: pasteboard) : nil
            let string: String? = if detected == .string {
                String(data: payload, encoding: .utf8) ?? pasteboard.string(forType: detected)
            } else if isText {
                pasteboard.string(forType: detected)
            } else {
                nil
            }
            return Selection(
                type: detected,
                payload: payload,
                string: string,
                sourceImageURL: stillPictureTypes.contains(detected) ? gifAddress(on: pasteboard, types: types) : nil,
                richPayload: rich
            )
        }
        // The plain text is read first and judged before any formatted flavour is, so a huge copy with an RTF or HTML
        // twin costs one read.
        let plainData = pasteboard.data(forType: .string)
        if let plainData,
           ClipSizePolicy.isTooLarge(
               byteCount: plainData.count,
               typeIdentifier: NSPasteboard.PasteboardType.string.rawValue
           )
        {
            return Selection(type: .string, payload: plainData, string: nil)
        }
        let rich = richFlavors(for: types, on: pasteboard)
        if let plain = plainData.flatMap({ String(data: $0, encoding: .utf8) }) ?? pasteboard.string(forType: .string) {
            return Selection(type: .string, payload: Data(plain.utf8), string: plain, richPayload: rich)
        }
        guard let data = pasteboard.data(forType: detected), data.count <= Self.maxRichTextBytes else { return nil }
        return Selection(type: .string, payload: Data(), string: nil, richText: (detected, data), richPayload: rich)
    }

    /// The file sits in a temporary folder that is emptied when the pasteboard moves on (ADR 0004), so a picture is
    /// kept
    /// as its bytes, now, and any other file is not kept.
    private static func remotePictureSelection(on pasteboard: any PasteboardReading) -> Selection? {
        guard let picture = RemoteFileClip.picture(from: pasteboard.fileURLs()) else { return nil }
        return Selection(type: picture.type, payload: picture.data, string: nil)
    }

    private static func richFlavors(
        for types: [NSPasteboard.PasteboardType], on pasteboard: any PasteboardReading
    )
    -> RichTextPayload? {
        let typeSet = Set(types)
        let rtf = typeSet.contains(.rtf) ? boundedRichData(for: .rtf, on: pasteboard) : nil
        let rtfd = typeSet.contains(.rtfd) ? boundedRichData(for: .rtfd, on: pasteboard) : nil
        let html = typeSet.contains(.html) ? boundedRichData(for: .html, on: pasteboard) : nil
        let payload = RichTextPayload(rtf: rtf, rtfd: rtfd, html: html)
        return payload.isEmpty ? nil : payload
    }

    private static func boundedRichData(
        for type: NSPasteboard.PasteboardType, on pasteboard: any PasteboardReading
    )
    -> Data? {
        guard let data = pasteboard.data(forType: type), !data.isEmpty, data.count <= maxRichTextBytes else {
            return nil
        }
        return data
    }

    private static func htmlSelection(
        for types: [NSPasteboard.PasteboardType], on pasteboard: any PasteboardReading
    )
    -> Selection? {
        guard types.contains(.html) else { return nil }
        if let html = pasteboard.string(forType: .html),
           let imageURL = ImageSourceAddress.imageURL(inHTML: html)
        {
            let imageType = imageURL.pathExtension.lowercased() == "gif"
                ? NSPasteboard.PasteboardType("com.compuserve.gif")
                : .png
            return Selection(type: imageType, payload: Data(), string: nil, sourceImageURL: imageURL)
        }
        guard let data = boundedRichData(for: .html, on: pasteboard) else { return nil }
        return Selection(
            type: .string,
            payload: Data(),
            string: nil,
            richText: (.html, data),
            richPayload: RichTextPayload(html: data)
        )
    }

    private static let stillPictureTypes: Set<NSPasteboard.PasteboardType> = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("org.webmproject.webp"),
        NSPasteboard.PasteboardType("public.webp")
    ]

    /// The GIF a browser's Copy Image came from, named in the HTML flavour next to the still picture.
    private static func gifAddress(on pasteboard: any PasteboardReading, types: [NSPasteboard.PasteboardType]) -> URL? {
        guard types.contains(.html), let html = pasteboard.string(forType: .html) else { return nil }
        return ImageSourceAddress.gifURL(inHTML: html)
    }

    /// Rich text is parsed in this process, on content any local program can put on the board. Past this size it is
    /// not worth parsing (a real paragraph is a few KB) and not safe to try.
    static let maxRichTextBytes = 1_000_000
}

/// The period the timer is running at, read and changed only by its own handler.
private final class PollPeriod: Sendable {
    private let value: Mutex<Duration>

    init(_ value: Duration) {
        self.value = Mutex(value)
    }

    /// True when `period` differs from the one running, which it then becomes.
    func change(to period: Duration) -> Bool {
        value.withLock { current in
            guard period != current else { return false }
            current = period
            return true
        }
    }
}

private extension Duration {
    /// `TimeInterval` (seconds) approximation for `DispatchSourceTimer.schedule`.
    var timeInterval: TimeInterval {
        let (sec, attoseconds) = components
        return TimeInterval(sec) + TimeInterval(attoseconds) / 1_000_000_000_000_000_000
    }
}

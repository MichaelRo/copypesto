// SPDX-License-Identifier: MIT
import AppKit
import CryptoKit
import ImageIO
import SwiftData

/// Ingest pipeline: PasteboardCapture → dedupe → sensitivity → source app → encrypt → SwiftData.
///
/// Runs as a ModelActor so all SwiftData writes happen on the dedicated model executor.
/// The injected `clock` parameter lets tests control the dedup window.
public actor StorageService: ModelActor {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer

    /// Not `@ModelActor`: the macro's initializer takes only the container, and what the service depends on arrives in
    /// `environment` (W-07).
    public init(modelContainer: ModelContainer, environment: StorageEnvironment = .live()) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        sequenceCounter = environment.sequenceCounter
        lastItemStore = environment.lastItemStore
        linkPreviews = environment.linkPreviews
        linkPreviewCache = environment.linkPreviewCache
        previewSealer = environment.previewSealer
        imageScreener = environment.imageScreener
        textRecognizer = environment.textRecognizer
        embedder = environment.embedder
        remoteGIFFetcher = environment.remoteGIFFetcher
        clock = environment.clock
        rules = environment.rules
        loadDeviceID = environment.deviceID
        keyRotator = environment.keyRotator
        undoHistory = environment.undoHistory
        wipeSuggestionLedger = environment.wipeSuggestionLedger
        nsfwModeProvider = environment.nsfwMode ?? { NSFWMode.current() }
    }

    /// The longest a copy kept from an allowed password manager stays in the history, whatever its allowance.
    static let concealedClipLifetime: TimeInterval = 86_400

    /// A kept copy goes when the allowance that let it in ends, and never later than a day after it was copied.
    static func concealedExpiry(timestamp: Date, allowanceEnd: Date?) -> Date {
        let cap = timestamp.addingTimeInterval(concealedClipLifetime)
        return allowanceEnd.map { min($0, cap) } ?? cap
    }

    /// Read by the app for the Edit menu and the banner; written only through this service and `ClipEditor`.
    public nonisolated let undoHistory: UndoHistory
    let wipeSuggestionLedger: (@Sendable () -> Void)?
    let nsfwModeProvider: @Sendable () -> NSFWMode
    let encryption = BlobEncryption()
    let keyRotator: @Sendable () throws -> Void
    let resolver = SourceAppResolver()
    /// Tracks the single most-recently-ingested hash with its timestamp. Used only to suppress
    /// the very-rapid re-capture of the *current latest* item (e.g. multiple paste echoes within
    /// a few hundred ms). Any other re-copy — including copying an older item again — must
    /// fall through to the contentHash dedup branch so its timestamp is bumped and it rises
    /// back to the top of history.
    var lastIngestedHash: (hash: String, seenAt: Date)?
    /// The clip the last ingest created (not one it re-dated), which a double ⌘C appends away (`appendToLatest`).
    var lastInsertedClip: (id: UUID, at: Date)?

    /// Retained for the lifetime of the actor so SequenceCounter preserves its in-memory
    /// counter across successive ingest calls — recreating it on every call would reload from
    /// UserDefaults and could emit duplicate sequence numbers under rapid ingestion.
    private let sequenceCounter: SequenceCounter
    private let loadDeviceID: @Sendable () throws -> String
    /// Cached after first Keychain lookup; the device ID never changes within a session.
    private var cachedDeviceID: String?

    /// Where the latest clip is mirrored for the CLI and AppleScript; injectable so tests do not share the real file.
    public let lastItemStore: any LastItemStoring

    let linkPreviews: LinkPreviewImageStore
    let linkPreviewCache: LinkPreviewCache

    /// Seals a preview with the given associated data; nil seals with the install's key.
    let previewSealer: (@Sendable (Data, Data) throws -> BlobEncryption.EncryptedEnvelope)?

    /// Decides whether a captured picture is sensitive.
    let imageScreener: any ImageSensitivityScreening

    /// Finds text in images.
    public let textRecognizer: any TextRecognizing

    /// Computes the search vector for new text clips. Only a normal launch loads the on-device language model; a test
    /// host gets none unless its environment names one, so no vector arrives from the background at a random moment.
    let embedder: any TextEmbedding

    var similarity = SimilarityIndex()
    var pendingEmbeddings: [UUID: Task<Void, Never>] = [:]
    var pendingAnalyses: [UUID: Task<Void, Never>] = [:]
    let remoteGIFFetcher: (@Sendable (URL) async -> Data?)?
    var runningAnalyses = 0
    var analysisQueue: [CheckedContinuation<Void, Never>] = []

    /// The clock, which a test moves to cross the 30-second dedup window. Starts as the environment's.
    public var clock: @Sendable () -> Date

    /// Ingest rules applied to text content before storage. Update via `updateRules(_:)`.
    public var rules: ClipboardRules

    public func updateRules(_ rules: ClipboardRules) {
        self.rules = rules
    }

    /// Encrypts previews stored in plaintext before every type was encrypted (URLs, images, files, and text from
    /// before ADR 0002). Idempotent; sensitive items keep their masked preview and colours stay plain.
    @discardableResult
    public func encryptLegacyPreviews() async throws -> Int {
        let colorRaw = ClipboardType.color.rawValue
        var changed = 0
        try await forEachClip(matching: FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.previewCiphertext == nil && !$0.previewText.isEmpty && $0.typeRaw != colorRaw }
        )) { item in
            guard item.sensitivityRaw == nil else { return }
            let envelope = try encryption.encrypt(
                Data(item.previewText.utf8),
                associatedData: BlobEncryption.associatedData(itemID: item.id, field: .preview)
            )
            item.previewCiphertext = envelope.ciphertext
            item.previewNonce = envelope.nonce
            item.previewAADBound = true
            item.previewText = ""
            changed += 1
        }
        return changed
    }

    public func updateClock(_ newClock: @escaping @Sendable () -> Date) {
        clock = newClock
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public func ingest(
        _ capture: PasteboardCapture,
        preferredItemID: UUID? = nil,
        rewritesText: Bool = true,
        popsLookalikePicture: Bool = true
    ) async throws {
        if ClipSizePolicy.isTooLarge(byteCount: capture.payload.count, typeIdentifier: capture.typeIdentifier) {
            throw ClipSizePolicy.TooLarge(message: ClipSizePolicy.message(
                byteCount: capture.payload.count, typeIdentifier: capture.typeIdentifier
            ))
        }
        let now = clock()
        let wholeIngest = PerfSignposts.copy.begin("ingest")
        let stages = PerfStages(PerfSignposts.copy, first: "dedup")
        defer {
            stages.finish()
            wholeIngest.end()
        }

        // 1. Suppress only the very-rapid re-capture of the *current latest* item (paste echo
        //    or repeated trigger within 2s). A re-copy of any OTHER item must fall through to
        //    the contentHash branch so its timestamp pops.
        // The watcher hands over a plain SHA-256; only a keyed form is ever stored (see `ContentHash`).
        let contentKey = try? encryption.loadOrCreateKey()
        let hash = ContentHash.stored(capture.contentHash, key: contentKey)
        let knownForms = ContentHash.candidates(for: capture.contentHash, key: contentKey)
        if let last = lastIngestedHash,
           last.hash == hash,
           now.timeIntervalSince(last.seenAt) < 2
        {
            return
        }

        // 2. Full-history dedup by contentHash. If this content already exists anywhere in the
        //    user's history, update the existing item's timestamp (pop to top) rather than
        //    creating a duplicate entry.
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { knownForms.contains($0.contentHash) }
        )
        if try await popExistingDuplicate(
            matching: descriptor,
            hash: hash,
            now: now,
            bundleID: capture.sourceBundleID,
            isRemote: capture.isRemote
        ) {
            return
        }

        stages.next("classify")
        // 2. Classify type from pasteboard UTI, then ContentClassifier for text.
        let pbType = NSPasteboard.PasteboardType(capture.typeIdentifier)
        let (clipType, classifiedLanguage) = clipboardType(for: pbType, payloadString: capture.payloadString)

        // 3. For images, compute pHash and skip if visually identical to a recent capture
        //    (runs before OCR so duplicates are never OCR-processed twice)
        //    (Hamming ≤ 5 against the last 50 stored images). This deduplicates screenshots
        //    taken milliseconds apart that differ only in timestamp metadata.
        stages.next("perceptualHash")
        var pixelWidth: Int?
        var pixelHeight: Int?
        var perceptualHash: String?
        if clipType == .image, let source = CGImageSourceCreateWithData(capture.payload as CFData, nil) {
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
                pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
            }
            let isLargeImage = capture.payload.count > 1_000_000 || (pixelWidth ?? 0) * (pixelHeight ?? 0) > 4_000_000
            if !isLargeImage {
                perceptualHash = PerceptualHasher.hash(imageSource: source)
            }
        }
        if let pHash = perceptualHash, let similar = perceptualDuplicate(of: pHash, payload: capture.payload) {
            if popsLookalikePicture {
                similar.timestamp = now
                try saveOrRollback()
            }
            return
        }

        // 4. Apply ingest rules to text content (URL tracking strip, whitespace normalization, etc.).
        stages.next("rules")
        let isLargeText = capture.payload.count > IngestAnalysisInput.backgroundTextBytes
        let (effectivePayload, effectiveString) = rewritesText && !isLargeText
            ? applyRules(to: capture, clipType: clipType)
            : (capture.payload, capture.payloadString)
        let payloadString = effectiveString ?? ""

        // 5. Judge the copy: the text in a picture (so it is searchable and a key in a screenshot is masked), the
        //    on-device model's verdict on a picture, the link check, and the scan of text for secrets. A picture or a
        //    very large text is saved first and judged afterwards, covered meanwhile (`analysisPending`); the rest is
        //    judged here, as before. OCR is skipped under UI test: the Vision model's cold start would delay every
        //    launch.
        let analysisInput = input(
            for: clipType, image: clipType == .image ? capture.payload : nil, text: payloadString,
            link: capture.payloadString
        )
        let judgedLater = analysisInput.runsInTheBackground
        var analysis = IngestAnalysis()
        if !judgedLater {
            stages.next("analysis")
            analysis = await Self.analyze(analysisInput, recognizer: textRecognizer, screener: imageScreener)
        }
        let ocrText = analysis.ocrText
        let detectedNSFW = analysis.isNSFW
        let detectedSensitivity = analysis.sensitivity

        // 6. Resolve source app (bundle ID → name + icon + dominant color).
        stages.next("resolveSourceApp")
        let appRecord: SourceAppRecord? = if let bundleID = capture.sourceBundleID {
            await resolver.resolve(bundleID: bundleID)
        } else {
            nil
        }

        // A copy a password manager marked as concealed, kept because the person allowed that app, may be a username
        // or a password: it is hidden either way, and shown only on request.
        // Everything that can suspend comes before the duplicate check below, so that nothing does between that check
        // and the insert: two copies of the same thing arriving together must find each other.
        if cachedDeviceID == nil { cachedDeviceID = try loadDeviceID() }
        guard let deviceID = cachedDeviceID else { throw BlobEncryption.Error.keychainAccessFailed(-1) }
        let seqNum = await sequenceCounter.next()
        stages.next("recheckDuplicate")
        let sensitivity = detectedSensitivity ?? (capture.isConcealed
            ? SensitiveContentDetector.Result(
                category: .credential, maskedPreview: "Hidden by \(appRecord?.displayName ?? "another app")"
            )
            : nil)

        // The awaits above (reading the picture, resolving the app) let another ingest of the same copy run to the
        // end, so the duplicate check is made again now that nothing suspends before the insert.
        if try await popExistingDuplicate(matching: descriptor, hash: hash, now: now, bundleID: nil) { return }

        stages.next("encrypt")
        // 7. Encrypt raw payload (use effectivePayload so rule-transformed text is stored).
        let itemID = preferredItemID ?? UUID()
        let blobAAD = BlobEncryption.associatedData(itemID: itemID, field: .blob)
        let envelope = try encryption.encrypt(effectivePayload, associatedData: blobAAD)
        let richEnvelope: BlobEncryption.EncryptedEnvelope? = if let rich = capture.richPayload, !rich.isEmpty {
            try encryption.encrypt(JSONEncoder().encode(rich), associatedData: blobAAD)
        } else {
            nil
        }

        // 8. Build and insert models. If the pasteboard UTI didn't tag this as a GIF but the
        //    raw bytes start with a GIF magic header, normalize the stored mimeType so the
        //    grid's fast-path animation check succeeds. NSBitmapImageRep is AppKit-only and
        //    unsafe off-main, so we match the magic header inline.
        let storedMimeType: String = {
            if clipType == .image, hasGIFMagicHeader(capture.payload) { return "com.compuserve.gif" }
            return capture.typeIdentifier
        }()
        let blob = ClipboardBlob(
            encryptedData: envelope.ciphertext,
            nonceData: envelope.nonce,
            mimeType: storedMimeType,
            encryptedRichData: richEnvelope?.ciphertext,
            richNonceData: richEnvelope?.nonce
        )
        // A clip judged afterwards has no preview until it is judged: nothing readable is stored that a secret in it
        // could
        // be part of.
        let preview = judgedLater
            ? (sensitivity?.maskedPreview ?? "")
            : (sensitivity?.maskedPreview ?? ocrText ?? String(payloadString.prefix(500)))
        let sealed = try storedPreview(for: itemID, clipType: clipType, sensitivity: sensitivity, preview: preview)
        let storedPreview = sealed.plain
        let previewEnvelope = sealed.envelope
        blob.aadBound = true
        let item = ClipboardItem(
            id: itemID,
            timestamp: capture.timestamp,
            type: clipType,
            sourceBundleID: capture.sourceBundleID,
            sourceAppName: capture.isRemote ? PasteboardCapture.remoteSourceName : appRecord?.displayName,
            sourceDominantColorHex: appRecord?.dominantColorHex,
            previewText: storedPreview,
            sensitivity: sensitivity?.category,
            sensitivityMaskedPreview: sensitivity?.maskedPreview,
            contentHash: hash,
            perceptualHash: perceptualHash,
            byteSize: effectivePayload.count,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            deviceID: deviceID,
            sequenceNumber: seqNum
        )
        item.previewCiphertext = previewEnvelope?.ciphertext
        item.previewNonce = previewEnvelope?.nonce
        item.previewAADBound = previewEnvelope != nil
        item.blob = blob
        item.detectedLanguage = classifiedLanguage
        item.textLength = clipType == .text || clipType == .code ? payloadString.count : 0
        item.isNSFW = detectedNSFW
        item.analysisPending = judgedLater
        item.isRemote = capture.isRemote
        if capture.isConcealed {
            item.expiresAt = Self.concealedExpiry(timestamp: capture.timestamp, allowanceEnd: capture.concealedUntil)
        }
        stages.next("save")
        modelContext.insert(item)
        modelContext.insert(blob)
        try saveOrRollback()
        stages.finish()
        lastIngestedHash = (hash, now)
        lastInsertedClip = (item.id, now)

        if clipType == .image, let source = capture.sourceImageURL, !hasGIFMagicHeader(capture.payload) {
            startGIFUpgrade(of: item.id, from: source)
        }
        if judgedLater {
            startAnalysis(of: item.id, input: analysisInput)
        } else {
            startEmbedding(for: item, text: payloadString)
            noteSignature(of: item, text: payloadString)
            mirrorToLastItemFile(item)
        }
    }

    /// Compute the sentence embedding for a text or code clip (on-device, detached utility task) and store it for
    /// semantic search.
    func startEmbedding(for item: ClipboardItem, text payloadString: String) {
        guard item.type == .text || item.type == .code, item.sensitivityRaw == nil, payloadString.count > 8 else {
            return
        }
        let hashToEmbed = item.contentHash
        let textToEmbed = SemanticIndexer.embeddingInput(for: payloadString)
        let taskID = UUID()
        let embedder = embedder
        pendingEmbeddings[taskID] = Task.detached(priority: .utility) { [self] in
            if let data = await embedder.embed(text: textToEmbed) {
                try? await self.storeEmbedding(contentHash: hashToEmbed, embeddingData: data)
            }
            await self.finishEmbedding(taskID)
        }
    }

    /// The last-item file is readable without the lock, so it is not written while the lock is on.
    func mirrorToLastItemFile(_ item: ClipboardItem) {
        if AppDefaults.store.value(for: Setting.biometricLockEnabled) {
            lastItemStore.clear()
        } else if item.sensitivityRaw == nil {
            lastItemStore.write(
                id: item.id,
                preview: item.displayPreviewText,
                type: item.typeRaw,
                timestamp: item.timestamp,
                sourceApp: item.sourceAppName
            )
        }
    }

    /// The preview as it is stored. It IS the content for short items (and OCR text, URLs and file paths can carry
    /// secrets), so every type except a parsed colour stores it only as ciphertext: the CloudKit-mirrored record
    /// carries
    /// nothing readable. Masked (sensitive) previews are safe by construction and stay plain. See ADR 0002.
    func storedPreview(
        for itemID: UUID, clipType: ClipboardType, sensitivity: SensitiveContentDetector.Result?, preview: String
    ) throws
    -> (plain: String, envelope: BlobEncryption.EncryptedEnvelope?) {
        let shouldEncrypt = sensitivity == nil && ColorPreviewPolicy.sealsPreview(of: clipType, preview: preview)
        if shouldEncrypt, let data = preview.data(using: .utf8) {
            return try ("", sealPreview(data, itemID: itemID))
        }
        return (preview, nil)
    }

    // MARK: - Bulk deletion

    /// Why items are being deleted. Only the person's own delete is a statement that a clip must not come back; ageing
    /// out, Clear Everything and a restore are not, so a backup can still bring those clips back.
    public enum DeletionReason: Sendable {
        case user
        case retention
        case clear
        case restore
        /// A clip that will not decrypt: it cannot be pasted or backed up. No tombstone, so a readable copy in an
        /// earlier backup can still be restored.
        case unreadable
        /// A clip folded into another by a double ⌘C (the echo of its first press). No tombstone: the text lives on.
        case merged
        /// An addition (an import, a new snippet) taken back with Undo. No tombstone, so it can be added again.
        case undone
    }

    /// Tombstones older than this are forgotten: they would otherwise grow forever and travel in every backup.
    public static let tombstoneLifetime: TimeInterval = 365 * 86_400

    /// The one way to delete items: removes every other copy of the content (the last-item file) and, for
    /// `.user`, records a tombstone so sync and re-import cannot resurrect them. A retention sweep also forgets
    /// tombstones past `tombstoneLifetime`.
    @discardableResult
    public func deleteItems(ids: [UUID], reason: DeletionReason, recordsUndo: Bool = true) throws -> Int {
        let doomed = try modelContext.fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { ids.contains($0.id) }
        ))
        let undoable = reason == .user && recordsUndo ? undoSnapshots(of: doomed) : nil
        let pages = doomed.filter { $0.type == .url }
            .compactMap { URL(string: $0.displayPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { [$0, LinkPreviewEligibility.fetchTarget(for: $0)].compactMap(\.self) }
        for item in doomed {
            if reason == .user { modelContext.insert(DeletedItemTombstone(id: item.id)) }
            modelContext.delete(item)
        }
        if reason == .retention { try pruneOldTombstones() }
        try saveOrRollback()
        if let undoable { undoHistory.record(UndoEntry(.clipsDeleted(undoable))) }
        PreviewTextCache.shared.clear()
        let deletedIDs = doomed.map(\.id)
        deletedIDs.forEach { similarity.remove($0) }
        linkPreviews.delete(ids: deletedIDs)
        linkPreviewCache.remove(pages)
        deletedIDs.forEach { lastItemStore.clear(ifItemID: $0) }
        return deletedIDs.count
    }

    private func pruneOldTombstones(now: Date = .now) throws {
        let cutoff = now.addingTimeInterval(-Self.tombstoneLifetime)
        let expired = try modelContext.fetch(FetchDescriptor<DeletedItemTombstone>(
            predicate: #Predicate { $0.deletedAt < cutoff }
        ))
        expired.forEach { modelContext.delete($0) }
    }

    /// Non-pinned items the range covers: everything from its start until now (all of it for `.all`).
    private func nonPinnedItems(in range: ClearRange, now: Date) throws -> [ClipboardItem] {
        let descriptor: FetchDescriptor<ClipboardItem> = if let start = range.start(now: now) {
            FetchDescriptor(predicate: #Predicate { !$0.isPinned && $0.timestamp >= start })
        } else {
            FetchDescriptor(predicate: #Predicate { !$0.isPinned })
        }
        return try modelContext.fetch(descriptor)
    }

    public func nonPinnedCount(in range: ClearRange, now: Date = .now) throws -> Int {
        try nonPinnedItems(in: range, now: now).count
    }

    @discardableResult
    public func clearNonPinned(in range: ClearRange, now: Date = .now) throws -> [UUID] {
        let items = try nonPinnedItems(in: range, now: now)
        let ids = items.map(\.id)
        undoHistory.clear()
        items.forEach { modelContext.delete($0) }
        try saveOrRollback()
        ids.forEach { similarity.remove($0) }
        PreviewTextCache.shared.clear()
        linkPreviews.delete(ids: ids)
        linkPreviewCache.clear()
        lastItemStore.clear()
        if range == .all {
            wipeSuggestionLedger?()
        }
        return ids
    }

    /// Deletes a single item by ID. Used for "burn after paste" items whose TTL has elapsed.
    /// Returns `true` if the item was found and deleted.
    @discardableResult
    public func deleteItem(id: UUID) throws -> Bool {
        try deleteItems(ids: [id], reason: .user) == 1
    }

    private func applyRules(to capture: PasteboardCapture, clipType: ClipboardType) -> (Data, String?) {
        guard let raw = capture.payloadString,
              clipType == .text || clipType == .url || clipType == .code else
        { return (
            capture.payload,
            capture.payloadString
        ) }
        let transformed = rules.apply(to: raw)
        return (Data(transformed.utf8), transformed)
    }

    /// GIF87a / GIF89a magic-byte check. Inlined here because `Data+GIF.swift` lives in the
    /// App-target `Shared/` module which `Core/` cannot import.
    private func hasGIFMagicHeader(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let prefix = Array(data.prefix(6))
        let gif87a: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]
        let gif89a: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]
        return prefix == gif87a || prefix == gif89a
    }

    // MARK: - Perceptual dedup

    func storeEmbedding(contentHash: String, embeddingData: Data) throws {
        let desc = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentHash == contentHash }
        )
        guard let item = try modelContext.fetch(desc).first else { return }
        item.embeddingData = embeddingData
        try saveOrRollback()
    }
}

private func clipboardType(
    for pbType: NSPasteboard.PasteboardType,
    payloadString: String?
)
-> (type: ClipboardType, detectedLanguage: String?) {
    switch pbType {
    case .png, .tiff,
         NSPasteboard.PasteboardType("public.jpeg"),
         NSPasteboard.PasteboardType("public.heic"),
         NSPasteboard.PasteboardType("org.webmproject.webp"),
         NSPasteboard.PasteboardType("public.webp"),
         NSPasteboard.PasteboardType("com.compuserve.gif"),
         NSPasteboard.PasteboardType("public.gif"),
         NSPasteboard.PasteboardType("com.adobe.pdf"),
         NSPasteboard.PasteboardType("public.svg-image"): return (.image, nil)
    case .fileURL: return (.file, nil)
    default:
        let result = ContentClassifier.classify(text: payloadString ?? "")
        return (result.type, result.detectedLanguage)
    }
}

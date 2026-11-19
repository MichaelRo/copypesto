// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

/// Keeps the Mac's widget snapshot (ADR 0059) as the iOS app keeps its own (ADR 0052): only while a Pesto widget is
/// installed; rewritten a moment after the history changes and at once when the lock, the cover or the theme does, one
/// write at a time so an older snapshot never lands after a newer one; a Locked or Hidden placeholder with no clip
/// while `WidgetSnapshotGate` says so; and with no widget, no file and no key. The app makes one only for a build
/// signed for the widget (`WidgetSharing`).
@MainActor
public final class WidgetSnapshotKeeper {
    /// Where the snapshot and its key live, and what WidgetKit says (nil when it could not say); a test names a
    /// temporary folder, a memory key store and its own answers.
    public struct Target {
        public let file: SealedGroupFile
        public let keys: SharedFileKeyStore
        public let isInstalled: @MainActor () async -> Bool?
        public let reload: @MainActor () -> Void

        public init(
            file: SealedGroupFile, keys: SharedFileKeyStore, isInstalled: @escaping @MainActor () async -> Bool?,
            reload: @escaping @MainActor () -> Void
        ) {
            self.file = file
            self.keys = keys
            self.isInstalled = isInstalled
            self.reload = reload
        }
    }

    /// What the app knows right now, asked before every write.
    public struct Inputs {
        public var gate: @MainActor () -> WidgetSnapshotGate
        public var theme: @MainActor () -> WidgetSnapshot.Theme
        /// False while the history cannot be read (the key is missing): no snapshot is kept then.
        public var canRead: @MainActor () -> Bool
        /// The source line a clip's card shows (its app, or Another device), read off the main actor.
        public var source: @Sendable (ClipboardItem) -> String?
        public var now: @MainActor () -> Date

        public init(
            gate: @escaping @MainActor () -> WidgetSnapshotGate, theme: @escaping @MainActor () -> WidgetSnapshot.Theme,
            canRead: @escaping @MainActor () -> Bool = { true },
            source: @escaping @Sendable (ClipboardItem) -> String?, now: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.gate = gate
            self.theme = theme
            self.canRead = canRead
            self.source = source
            self.now = now
        }
    }

    private struct Written: Equatable {
        let gate: WidgetSnapshotGate
        let theme: WidgetSnapshot.Theme
    }

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Widget")

    private let target: Target
    private let container: ModelContainer
    private let inputs: Inputs
    private let rewriteDelay: Duration
    private var observer: (any NSObjectProtocol)?
    private var rewrite: Task<Void, Never>?
    private var writes: Task<Void, Never>?
    private var lastSnapshot: WidgetSnapshot?
    private var lastWritten: Written?
    public private(set) var isInstalled = false

    public init(
        target: Target, container: ModelContainer, inputs: Inputs,
        rewriteDelay: Duration = WidgetSnapshotPolicy.rewriteDelay
    ) {
        self.target = target
        self.container = container
        self.inputs = inputs
        self.rewriteDelay = rewriteDelay
    }

    /// Stops following the history; the file stays as it is.
    public func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        rewrite?.cancel()
        rewrite = nil
    }

    /// Follows the history's saves and asks WidgetKit once.
    public func start() async {
        if observer == nil {
            observer = ModelSaveObserver.observeChanges(in: container) { [weak self] _ in self?.historyChanged() }
        }
        await refreshPresence()
    }

    /// Asks whether a Pesto widget is installed. A widget that appeared, or one with nothing written for it yet, gets
    /// the snapshot now; one already kept is left alone (saves and state changes keep it current), so asking costs no
    /// Keychain read, seal or reload on the shelf's way open. None installed, the file and the key go (and with no file
    /// left, the Keychain is not touched). WidgetKit failing to answer changes nothing: it is not a removed widget.
    public func refreshPresence() async {
        guard let installed = await target.isInstalled() else { return }
        let appeared = installed && !isInstalled
        isInstalled = installed
        if installed {
            if appeared || lastWritten == nil { await write() }
        } else if target.file.exists {
            remove()
        }
    }

    public func historyChanged() {
        guard isInstalled else { return }
        rewrite?.cancel()
        rewrite = Task { [weak self, rewriteDelay] in
            try? await Task.sleep(for: rewriteDelay)
            guard !Task.isCancelled else { return }
            await self?.write()
        }
    }

    /// The lock, the cover or the theme may have moved: a snapshot that no longer matches them is written again now.
    public func stateMayHaveChanged() async {
        guard isInstalled, lastWritten != Written(gate: inputs.gate(), theme: inputs.theme()) else { return }
        await write()
    }

    /// Writes what the store holds now, after any write still running.
    public func write() async {
        rewrite?.cancel()
        rewrite = nil
        let previous = writes
        let next = Task { [weak self] in
            await previous?.value
            await self?.performWrite()
        }
        writes = next
        await next.value
    }

    public func remove() {
        rewrite?.cancel()
        rewrite = nil
        lastSnapshot = nil
        lastWritten = nil
        target.file.remove()
        target.keys.remove()
        target.reload()
    }

    private func performWrite() async {
        guard isInstalled else { return }
        guard inputs.canRead() else { return dropFile() }
        let theme = inputs.theme()
        let gate = inputs.gate()
        if let placeholder = gate.placeholder(theme: theme, at: inputs.now()) {
            return store(placeholder, as: Written(gate: gate, theme: theme))
        }
        do {
            let snapshot = try await Self.snapshot(
                container: container, now: inputs.now(), theme: theme, previous: lastSnapshot, source: inputs.source
            )
            // The lock or the cover may have come on while the clips were read.
            let after = inputs.gate()
            guard after == .clips else {
                return store(after.placeholder(theme: theme, at: inputs.now()), as: Written(gate: after, theme: theme))
            }
            store(snapshot, as: Written(gate: gate, theme: theme))
        } catch {
            Self.logger.error("The widget snapshot was not read: \(error.localizedDescription, privacy: .public)")
            dropFile()
        }
    }

    private func store(_ snapshot: WidgetSnapshot?, as written: Written) {
        // The widget may have gone while the clips were read: `remove()` has run, and nothing may bring the file or
        // the key back.
        guard isInstalled else { return }
        guard let snapshot else { return dropFile() }
        do {
            try target.file.write(snapshot, with: target.keys.loadOrCreate())
            lastSnapshot = snapshot.clips.isEmpty && snapshot.pinned.isEmpty ? nil : snapshot
            lastWritten = written
            target.reload()
        } catch {
            Self.logger.error("The widget snapshot was not written: \(error.localizedDescription, privacy: .public)")
            dropFile()
        }
    }

    /// A snapshot that could not be written again must not leave the old one behind: it may hold a clip deleted or
    /// made secret since.
    private func dropFile() {
        lastSnapshot = nil
        lastWritten = nil
        guard target.file.exists else { return }
        target.file.remove()
        target.reload()
    }

    /// Off the main actor, with a context of its own, so decoding a picture's thumbnail does not hold up the shelf.
    @concurrent
    private static func snapshot(
        container: ModelContainer, now: Date, theme: WidgetSnapshot.Theme, previous: WidgetSnapshot?,
        source: @escaping @Sendable (ClipboardItem) -> String?
    ) async throws
    -> WidgetSnapshot {
        try WidgetSnapshotSelection.snapshot(
            in: ModelContext(container), now: now, theme: theme, previous: previous, source: source
        )
    }
}

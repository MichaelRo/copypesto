// SPDX-License-Identifier: MIT
import Foundation
import Observation
import os
import SwiftData

/// The whole history, newest first, for the two surfaces that show it: the shelf and the floating window. Each used to
/// hold its own live `@Query` over every clip (two whole-table fetches, both kept live for the life of the app once a
/// window had been opened). This is one fetch on the main context both windows already use, so the clips are the same
/// objects the cards edit and save. It is loaded at launch (`prefetch`) and then follows every save from what the save
/// changed (`HistorySaveChange`), shown or not: a copy is inserted at the front, a re-copy moves, a delete goes, and
/// the
/// search index follows. Reading the whole history again took 100 ms on the main thread, and it happened inside the
/// shelf opening whenever a copy had been made while it was closed (222 ms to open instead of 53). The whole read is
/// kept for a large change, for a save that does not say what it changed, and after memory pressure (`trim`) has let
/// the history go.
@MainActor
@Observable
public final class HistoryStore {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HistoryStore")
    private static let incrementalLimit = 200
    private static let indexSlice = 250

    public private(set) var items: [ClipboardItem] = []

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var isStale = true
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var itemsByID: [UUID: ClipboardItem] = [:]
    @ObservationIgnored private var index: HistoryIndex?
    @ObservationIgnored private var build: IndexBuild?
    @ObservationIgnored private var buildTask: Task<Void, Never>?
    @ObservationIgnored private var memoryPressure: (any DispatchSourceMemoryPressure)?
    /// How many times the history was read; a test asserts a hidden store does not.
    @ObservationIgnored public private(set) var fetchCount = 0

    /// The rows of an index being built a few hundred at a time, so a first show over thousands of clips never holds
    /// the main thread for a frame.
    private struct IndexBuild {
        var remaining: ArraySlice<ClipboardItem>
        var rows: [HistoryRow] = []
    }

    public init(container: ModelContainer) {
        context = container.mainContext
        observer = ModelSaveObserver.observeChanges(in: container) { [weak self] change in
            self?.historyWasSaved(change)
        }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.trim() }
        }
        pressure.resume()
        memoryPressure = pressure
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Called as the shelf or the floating window appears or goes away (`visible` is true while either is on screen).
    public func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible, isStale { refresh() }
        if !visible {
            pendingRefresh?.cancel()
            pendingRefresh = nil
        }
    }

    /// Loads the history before anyone asks for it, so the first show finds it ready. Does nothing once loaded.
    public func prefetch() {
        if isStale || (index == nil && build == nil) { refresh() }
    }

    /// Lets go of the history (memory pressure). The next show, or the next prefetch, reads it again.
    public func trim() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        buildTask?.cancel()
        build = nil
        index = nil
        items = []
        itemsByID = [:]
        isStale = true
    }

    public func item(for id: UUID) -> ClipboardItem? {
        itemsByID[id]
    }

    public var hasSearchText: Bool {
        index?.hasSearchText ?? false
    }

    /// The history as rows, for filtering without touching a clip. Finishes a build still under way, and rebuilds the
    /// text after `dropSearchText()`. Nil only before the first fetch.
    public func searchIndex() -> HistoryIndex? {
        if build != nil { finishBuild() }
        if index == nil || index?.hasSearchText == false {
            guard fetchCount > 0 else { return nil }
            index = HistoryIndex(items: items)
        }
        return index
    }

    /// The history locked or was cleared: the decrypted text goes with `PreviewTextCache`.
    public func dropSearchText() {
        buildTask?.cancel()
        build = nil
        index?.dropSearchText()
    }

    /// A clip was edited in a way the index reads (title, note, tags, collection, the sensitive mark).
    public func refreshRow(for item: ClipboardItem) {
        guard var current = searchIndex() else { return }
        current.apply(upserting: [item])
        index = current
        itemsByID[item.id] = item
    }

    public func refresh() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        fetchCount += 1
        isStale = false
        let fetching = PerfSignposts.shelf.begin("historyRefresh")
        defer { fetching.end() }
        let descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        do {
            items = try context.fetch(descriptor)
            itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            startIndexBuild()
        } catch {
            isStale = true
            Self.logger.error("History fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns once a refresh that a save started has run. For tests.
    public func waitForRefresh() async throws {
        try await Task.sleep(for: .milliseconds(150))
        await pendingRefresh?.value
    }

    // MARK: - Following saves

    private func historyWasSaved(_ change: HistorySaveChange?) {
        if let change, change.touchesNoClip { return }
        guard let change, build == nil, index != nil, change.count <= Self.incrementalLimit else {
            // Not loaded, or not told what changed: read it all again, now if someone is looking and at the next show
            // if not.
            if isVisible { scheduleRefresh() } else { isStale = true }
            return
        }
        apply(change)
    }

    private func apply(_ change: HistorySaveChange) {
        guard var current = index else { return }
        let following = PerfSignposts.shelf.begin("historyApply")
        defer { following.end() }
        if !change.deleted.isEmpty {
            let gone = Set(change.deleted)
            for row in current.rows where gone.contains(row.modelID) {
                itemsByID[row.id] = nil
            }
            current.apply(removing: gone)
        }
        let changed = Set(change.inserted + change.updated)
        if !changed.isEmpty {
            let descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { changed.contains($0.persistentModelID) }
            )
            do {
                let fetched = try context.fetch(descriptor)
                for item in fetched {
                    itemsByID[item.id] = item
                }
                current.apply(upserting: fetched)
            } catch {
                Self.logger.error("History change fetch failed: \(error.localizedDescription, privacy: .public)")
                scheduleRefresh()
                return
            }
        }
        index = current
        items = current.rows.compactMap { itemsByID[$0.id] }
    }

    private func scheduleRefresh() {
        isStale = true
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            // A burst of saves (several copies in a row) becomes one read.
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - Building the index

    private func startIndexBuild() {
        buildTask?.cancel()
        index = nil
        build = IndexBuild(remaining: items[...])
        buildTask = Task { [weak self] in
            while let self, self.build != nil, !Task.isCancelled {
                self.buildSlice(Self.indexSlice)
                try? await Task.sleep(for: .milliseconds(4))
            }
        }
    }

    private func buildSlice(_ count: Int) {
        guard var current = build else { return }
        let slice = current.remaining.prefix(count)
        current.rows.append(contentsOf: slice.map { HistoryRow($0) })
        current.remaining = current.remaining.dropFirst(slice.count)
        if current.remaining.isEmpty {
            index = HistoryIndex(rows: current.rows)
            build = nil
        } else {
            build = current
        }
    }

    private func finishBuild() {
        buildTask?.cancel()
        while build != nil {
            buildSlice(Self.indexSlice)
        }
    }
}

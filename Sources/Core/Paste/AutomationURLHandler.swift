// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Runs `pesto://` links for automation (Alfred, Keyboard Maestro, shell scripts):
///
///     pesto://open                         show the shelf
///     pesto://list                         open the floating window
///     pesto://search?q=<text>              show the shelf with the search filled in
///     pesto://paste?id=<UUID>              paste a clip by id, without the shelf
///     pesto://pin?id=<UUID>                pin or unpin a clip by id
///     pesto://collection?name=<name>       switch the collection by name, ignoring case (`pinboard` is the old name)
///     pesto://clear?range=hour|today|all   after the person confirms, delete the unpinned clips of that span
///     pesto://summary?id=<UUID>            show the shelf searching for that clip (never calls an AI provider)
///
/// While the history is locked a link opens the lock screen and does nothing else: it must not set state behind it.
@MainActor
public final class AutomationURLHandler {
    /// A link asks the person to confirm a clear. Asking again within this time is ignored, so a page cannot keep the
    /// dialog up.
    static let clearCooldown: TimeInterval = 30

    private weak var host: (any AutomationHost)?
    private let now: () -> Date
    private var lastClearRequest: Date?

    public init(host: any AutomationHost, now: @escaping () -> Date = { Date() }) {
        self.host = host
        self.now = now
    }

    public func handle(_ url: URL) {
        guard let request = AutomationRequest(url: url) else { return }
        run(request)
    }

    /// The task is returned for a request that waits on the store, so a test can wait for it.
    @discardableResult
    func run(_ request: AutomationRequest) -> Task<Void, Never>? {
        guard let host else { return nil }
        switch request {
        case .open:
            host.showShelf()
        case .list:
            host.togglePinnedWindow()
        case let .search(query):
            host.showShelf()
            // A link must not pre-load a search behind the lock screen.
            if let query, !host.isHistoryLocked { host.search(for: query) }
        case let .pin(id):
            guard !host.isHistoryLocked else { return nil }
            return Task { [weak host] in await host?.togglePin(id: id) }
        case let .clear(range):
            let moment = now()
            if let last = lastClearRequest, moment.timeIntervalSince(last) < Self.clearCooldown { return nil }
            lastClearRequest = moment
            return Task { [weak host] in host?.requestClear(range) }
        case let .paste(id):
            return whenUnlocked(host) { Self.pasteTask(id, host) }
        case let .collection(name):
            return whenUnlocked(host) { Self.collectionTask(name, host) }
        case let .summary(id):
            return whenUnlocked(host) { Self.summaryTask(id, host) }
        }
        return nil
    }

    /// A link that reads the store does nothing without one, and while the history is locked only opens the lock
    /// screen.
    private func whenUnlocked(_ host: any AutomationHost, _ task: () -> Task<Void, Never>) -> Task<Void, Never>? {
        guard host.historyContainer != nil else { return nil }
        guard !host.isHistoryLocked else {
            host.showShelf()
            return nil
        }
        return task()
    }

    private static func pasteTask(_ id: UUID, _ host: some AutomationHost) -> Task<Void, Never> {
        Task { [weak host] in
            withItem(id: id, in: host?.historyContainer) { host?.paste($0) }
        }
    }

    private static func collectionTask(_ name: String, _ host: some AutomationHost) -> Task<Void, Never> {
        Task { [weak host] in
            guard let host, let container = host.historyContainer else { return }
            host.selectCollection(collection(named: name, in: container)?.id)
            host.showShelf()
        }
    }

    private static func summaryTask(_ id: UUID, _ host: some AutomationHost) -> Task<Void, Never> {
        Task { [weak host] in
            withItem(id: id, in: host?.historyContainer) { item in
                let preview = item.displayPreviewText
                guard item.sensitivityRaw == nil, preview.count > 8 else { return }
                host?.showShelf()
                // Summarizing stays a deliberate click on the card's Summarize button: a link must not send clip text
                // to a provider.
                host?.search(for: String(preview.prefix(40)))
            }
        }
    }

    /// The clip is only valid while its context lives, so the work with it happens inside.
    private static func withItem(id: UUID, in container: ModelContainer?, _ body: (ClipboardItem) -> Void) {
        guard let container else { return }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try? context.fetch(descriptor).first else { return }
        body(item)
    }

    private static func collection(named name: String, in container: ModelContainer) -> Pinboard? {
        let descriptor = FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? ModelContext(container).fetch(descriptor))?.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
}

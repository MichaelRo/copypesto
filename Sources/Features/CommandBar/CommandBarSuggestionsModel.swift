// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore

/// Keeps the command bar's tag and app chips current without a live query over the whole history: the storage actor
/// counts them, and this reloads only while a shelf is on screen, a moment after the history last changed.
@MainActor
@Observable
final class CommandBarSuggestionsModel {
    private(set) var suggestions = CommandBarSuggestions.empty
    /// The app in front when the shelf opened. It lives here, not on `AppState`, so the grid is not invalidated, and
    /// it is read again at every open: the chip row would otherwise keep the first app it saw.
    private(set) var frontmost: SourceApp?

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let observesSaves: Bool

    init(debounce: Duration = .milliseconds(500), observesSaves: Bool = true) {
        self.debounce = debounce
        self.observesSaves = observesSaves
    }

    func start(_ appState: AppState) {
        self.appState = appState
        if observesSaves, observer == nil {
            observer = ModelSaveObserver.observe { [weak self] in self?.refresh(afterDelay: true) }
        }
        refresh()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        pending?.cancel()
        pending = nil
    }

    func refresh(afterDelay: Bool = false) {
        syncFrontmost()
        pending?.cancel()
        let delay = afterDelay ? debounce : nil
        pending = Task { [weak self] in
            if let delay {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            await self?.load()
        }
    }

    func syncFrontmost() {
        let current = appState?.frontmostAppBundleID.flatMap { id in
            appState?.frontmostAppName.map { SourceApp(bundleID: id, name: $0) }
        }
        if current != frontmost { frontmost = current }
    }

    func settle() async {
        await pending?.value
    }

    private func load() async {
        guard let appState else { return }
        guard !appState.isHistoryLocked else {
            suggestions = .empty
            return
        }
        guard appState.isOverlayVisible || appState.isPinnedWindowVisible,
              let loader = appState.commandBarSuggestions else { return }
        let result = await loader() ?? .empty
        guard !Task.isCancelled, !appState.isHistoryLocked, result != suggestions else { return }
        suggestions = result
    }
}

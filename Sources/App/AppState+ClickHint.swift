// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

extension AppState {
    static let clickHintDuration: Duration = .seconds(4)

    func noteShelfClick(_ click: ShelfClick, tap: ShelfTap) {
        if ClickHintPolicy.isDoubleClickPaste(click: click, tap: tap) {
            AppDefaults.store.set(true, for: Setting.doubleClickPasted)
        }
        guard click == .single, tap == .focus else { return hideClickHint() }
        guard !isClickHintVisible else { return }
        guard ClickHintPolicy.shouldShow(
            timesShown: AppDefaults.store.value(for: Setting.clickHintShownCount),
            hasDoubleClickPasted: AppDefaults.store.value(for: Setting.doubleClickPasted),
            tap: tap
        ) else { return }
        clickHintTask?.cancel()
        clickHintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled, let self, isOverlayVisible else { return }
            isClickHintVisible = true
            try? await Task.sleep(for: Self.clickHintDuration)
            guard !Task.isCancelled else { return }
            isClickHintVisible = false
        }
    }

    func noteClickHintDrawn() {
        let shown = AppDefaults.store.value(for: Setting.clickHintShownCount)
        AppDefaults.store.set(shown + 1, for: Setting.clickHintShownCount)
    }

    func hideClickHint() {
        clickHintTask?.cancel()
        clickHintTask = nil
        if isClickHintVisible { isClickHintVisible = false }
    }
}

// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// Gets the first screenful of the shelf ready a few seconds after launch, so the first open is not the first time
/// anything
/// is decrypted, drawn or decoded: the newest clips' previews and metadata, their source apps' icons and, for pictures,
/// the
/// thumbnail a card would load. Only what the shelf shows first (a dozen clips), never the history, and everything goes
/// into
/// the caches the cards already use and bound, so the footprint grows by a few megabytes at most. Skipped while the
/// history is
/// locked, while the shelf is open, and when the Mac is busy enough that the history has not loaded.
@MainActor
enum ShelfPrewarm {
    static let clipCount = 12
    static let delay = Duration.seconds(5)

    static var isEnabled: Bool {
        let configuration = RuntimeConfiguration.current
        switch configuration.mode {
        case .normal: return true
        case .uiTest:
            // Benchmarks only: a UI test must not see work it did not ask for, and `PESTO_NO_PREWARM` is the A/B's off.
            return configuration.recordsPerfTimeline && ProcessInfo.processInfo.environment["PESTO_NO_PREWARM"] != "1"
        default: return false
        }
    }

    static func run(appState: AppState, layoutShelf: @MainActor () -> Void) async {
        guard isEnabled else { return }
        try? await Task.sleep(for: delay)
        // A locked history shows the lock screen, whose Touch ID prompt must not start in a shelf nobody opened, and a
        // Mac on battery saver has asked for no extra work.
        guard !appState.isHistoryLockedNow(), !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        guard let store = appState.historyStore, let container = appState.historyContainer else { return }
        let started = ContinuousClock.now
        let interval = PerfSignposts.shelf.begin("prewarm")
        defer { interval.end() }
        for item in store.items.prefix(clipCount) {
            guard !appState.isOverlayVisible, !appState.isHistoryLockedNow() else { return }
            _ = item.displayPreviewText
            _ = item.metadata
            _ = SourceIconCache.shared.image(forBundleID: item.sourceBundleID)
            if item.type == .image, ThumbnailCache.shared.entry(for: item.id, byteSize: item.byteSize) == nil {
                let service = await ThumbnailServices.shared.service(for: container)
                if let result = await service.thumbnail(for: item.id, maxPixel: 480),
                   let image = await PreparedImage.image(from: result.data, animated: result.isAnimated)
                {
                    ThumbnailCache.shared.store(
                        .init(image: image, isAnimated: result.isAnimated, byteSize: item.byteSize), for: item.id
                    )
                }
            }
            await Task.yield()
        }
        if !appState.isOverlayVisible { layoutShelf() }
        PerfSignposts.shelf.event("prewarmDone", "\((ContinuousClock.now - started).formatted())")
    }
}

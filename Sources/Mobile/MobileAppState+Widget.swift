// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore
import SwiftData

/// The Recent Clips widget's snapshot (ADR 0052): kept only while a Pesto widget is installed, asked when Pesto becomes
/// active and when it leaves the foreground; rewritten a moment after the history changes, one write at a time;
/// emptied at once by Clear History; with no widget, no file and no key.
extension MobileAppState {
    private static let widgetLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "Widget")

    func startWidget(container: ModelContainer) {
        widgetObserver = ModelSaveObserver.observeChanges(in: container) { [weak self] _ in
            self?.widgetHistoryChanged()
        }
        Task { await refreshWidgetPresence() }
    }

    /// Asks iOS whether a Pesto widget is installed: one is, the snapshot is written now; none is, the file and the key
    /// go (and with no file left, the Keychain is not touched).
    func refreshWidgetPresence() async {
        guard let target = widget else { return }
        widgetIsInstalled = await target.isInstalled()
        if widgetIsInstalled {
            await writeWidget()
        } else if target.file.exists {
            removeWidget()
        }
    }

    func widgetHistoryChanged() {
        guard widgetIsInstalled else { return }
        widgetRewrite?.cancel()
        widgetRewrite = Task { [weak self] in
            try? await Task.sleep(for: WidgetSnapshotPolicy.rewriteDelay)
            guard !Task.isCancelled else { return }
            await self?.writeWidget()
        }
    }

    /// Writes the snapshot of what the store holds now, after any write still running, so an older snapshot never
    /// lands after a newer one.
    func writeWidget() async {
        widgetRewrite?.cancel()
        widgetRewrite = nil
        await enqueueWidgetWrite { state in await state.performWidgetWrite() }
    }

    /// Clear History: nothing it removed may stay on the Home Screen, so an empty snapshot is written before anything
    /// is chosen again.
    func emptyWidget() async {
        widgetRewrite?.cancel()
        widgetRewrite = nil
        guard let target = widget, widgetIsInstalled || target.file.exists else { return }
        await enqueueWidgetWrite { state in state.performWidgetEmpty() }
    }

    func removeWidget() {
        guard let target = widget else { return }
        widgetRewrite?.cancel()
        widgetRewrite = nil
        lastWidgetSnapshot = nil
        target.file.remove()
        target.keys.remove()
        target.reload()
    }

    private func enqueueWidgetWrite(_ body: @escaping @MainActor (MobileAppState) async -> Void) async {
        let previous = widgetWrites
        let next = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await body(self)
        }
        widgetWrites = next
        await next.value
    }

    private func performWidgetWrite() async {
        guard let target = widget, widgetIsInstalled, let container = historyContainer else { return }
        if historyLock.holdsOutsideSurfaces {
            performWidgetEmpty()
            return
        }
        let previous = lastWidgetSnapshot
        do {
            let snapshot = try await Self.widgetSnapshot(
                container: container, now: clock(), theme: Self.widgetTheme(), previous: previous,
                device: CardFootLineView.device
            )
            guard !historyLock.holdsOutsideSurfaces else { return performWidgetEmpty() }
            try target.file.write(snapshot, with: target.keys.loadOrCreate())
            lastWidgetSnapshot = snapshot
            target.reload()
        } catch {
            Self.widgetLogger
                .error("The widget snapshot was not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    func performWidgetEmpty() {
        guard let target = widget else { return }
        lastWidgetSnapshot = nil
        let theme = Self.widgetTheme()
        let snapshot = historyLock.holdsOutsideSurfaces
            ? WidgetSnapshot.locked(theme: theme, at: clock()) : WidgetSnapshot.empty(theme: theme, at: clock())
        do {
            try target.file.write(snapshot, with: target.keys.loadOrCreate())
        } catch {
            Self.widgetLogger
                .error("The widget snapshot was not emptied: \(error.localizedDescription, privacy: .public)")
            target.file.remove()
        }
        target.reload()
    }

    /// Off the main actor, with a context of its own: it reads what the store holds now (a clip the storage actor just
    /// made secret, say), and decoding a new picture's thumbnail does not hold up the library.
    @concurrent
    private static func widgetSnapshot(
        container: ModelContainer, now: Date, theme: WidgetSnapshot.Theme, previous: WidgetSnapshot?,
        device: CardFootLine.Device
    ) async throws
    -> WidgetSnapshot {
        try WidgetSnapshotSelection.snapshot(in: ModelContext(container), now: now, theme: theme, previous: previous) {
            CardFootLine.source(CardFootLine.origin(of: $0), device: device).name
        }
    }

    static func widgetTheme() -> WidgetSnapshot.Theme {
        let defaults = AppDefaults.store
        func resolve(dark: Bool) -> MobileTheme {
            MobileTheme.resolve(
                accent: defaults.value(for: Setting.accentColorHex), theme: defaults.value(for: Setting.appTheme),
                darkTheme: defaults.value(for: Setting.appThemeDark), isDark: dark
            )
        }
        let light = resolve(dark: false)
        let dark = resolve(dark: true)
        return WidgetSnapshot.Theme(
            lightGround: light.groundHex, darkGround: dark.groundHex, lightAccent: light.accentHex,
            darkAccent: dark.accentHex
        )
    }
}

// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// The Recent Clips widget's snapshot (ADR 0059), kept only by a build signed for it and only while a widget is
/// installed. WidgetKit never tells the app a widget was added, so Pesto asks at launch, when the shelf opens (a
/// widget's message opens it), on a link, on wake and every ten minutes.
extension AppDelegate {
    static let widgetPresenceInterval: TimeInterval = 600

    func startWidgetIfSigned() {
        guard widgetKeeper == nil, let target = MacWidgetTarget.current,
              let container = appState.historyContainer else { return }
        let state = appState
        let keeper = WidgetSnapshotKeeper(target: target, container: container, inputs: .init(
            gate: {
                WidgetSnapshotGate.decide(
                    widgetsEnabled: AppDefaults.store.value(for: Setting.widgetsEnabled),
                    lockEnabled: AppDefaults.store.value(for: Setting.biometricLockEnabled),
                    isCovered: state.isContentCovered(
                        screenSharingPrivacy: AppDefaults.store.value(for: Setting.screenSharingPrivacy)
                    )
                )
            },
            theme: {
                let defaults = AppDefaults.store
                return WidgetSnapshot.Theme.resolve(
                    accent: defaults.value(for: Setting.accentColorHex), theme: defaults.value(for: Setting.appTheme),
                    darkTheme: defaults.value(for: Setting.appThemeDark)
                )
            },
            canRead: { !state.isEncryptionKeyUnresolved },
            source: { $0.isRemote ? PasteboardCapture.remoteSourceName : $0.knownSourceAppName },
            appIcon: { SourceIconCache.shared.pngData(forBundleID: $0) }
        ))
        widgetKeeper = keeper
        appState.onContentCoverChanged = { [weak keeper] in Task { await keeper?.stateMayHaveChanged() } }
        appState.collectionLockChanged = { [weak keeper] in Task { await keeper?.write() } }
        let interval = Self.widgetPresenceInterval
        widgetPresenceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak keeper] _ in
            Task { @MainActor in await keeper?.refreshPresence() }
        }
        Task { await keeper.start() }
    }

    func refreshWidgetPresence() {
        guard let keeper = widgetKeeper else { return }
        Task { await keeper.refreshPresence() }
    }

    /// A Setting moved (the lock, the cover's setting, the theme or the accent): rewritten only if what it holds would
    /// differ.
    func widgetSettingsChanged() async {
        await widgetKeeper?.stateMayHaveChanged()
    }

    /// After a clear, the snapshot is rewritten from what the store holds before anything else runs, so nothing that
    /// was cleared stays on the desktop.
    func rewriteWidgetAfterClear() async {
        await widgetKeeper?.write()
    }
}

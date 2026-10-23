// SPDX-License-Identifier: MIT
import PestoCore

extension AppDelegate {
    /// Work that can wait until the app is up: moving old data out of history rows, and loading the screening model.
    func runLaunchMaintenance() {
        runHeavyColumnMigration()
        removeLegacyAIKeysOnce()
        prewarmImageScreeningIfNeeded()
        Task.detached(priority: .utility) { await OCRService().prewarm() }
        // A clip saved before it was judged, when the app last quit, is judged now.
        if let service = storageService { Task { await service.resumePendingAnalysis() } }
        // The first show should not wait for the history: it is read now, while nobody is looking.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.appState.historyStore?.prefetch()
        }
    }

    /// The first screening after launch used to wait for the model to load. When the filter is on, load it now.
    func prewarmImageScreeningIfNeeded() {
        guard NSFWMode.current().detectsContent else { return }
        Task.detached(priority: .utility) { AppleIntelligenceClient.prewarmVision() }
    }

    /// Earlier builds could keep a Claude, ChatGPT or Gemini key in the Keychain; Pesto no longer uses any of them.
    private func removeLegacyAIKeysOnce() {
        guard LaunchMode.current.usesSystemIntegrations,
              !AppDefaults.store.value(for: Setting.legacyAIKeysRemoved) else { return }
        LegacyAIKeyCleanup.run()
        AppDefaults.store.set(true, for: Setting.legacyAIKeysRemoved)
    }
}

// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

extension AppDelegate {
    func startPasteboardWatcher() {
        ExclusionAllowances().clear()
        removeKeptConcealedCopies(from: nil)
        reviewAllowances()
        let watcher = PasteboardWatcher(exclusionRules: currentExclusionRules(), ownWrites: appState.ownWrites)
        appState.pasteboardWatcher = watcher
        let stats = PrivacyStatsStore()
        Task { await watcher.onBlocked { stats.record($0) } }
        appState.startLockWatchdog()
        if let service = storageService {
            appState.privacySnapshot = { try? await service.privacySnapshot() }
            appState.commandBarSuggestions = { try? await service.commandBarSuggestions() }
            appState.clearEverything = { [weak self] in
                ThumbnailCache.shared.clear()
                LinkPreviewCache.shared.clear()
                QuickLookPreviewController.sweepStaleTempFiles()
                self?.appState.clearShelfSuggestions()
                return try await service.clearEverything()
            }
        }

        watcherTask = Task.detached(priority: .utility) {
            await watcher.start(adaptive: true)
        }
        if let service = storageService {
            let state = appState
            let pipeline = CapturePipeline(
                storage: service, appendMode: appendCoordinator,
                didStore: { await SoundEffects.play(.copy) },
                didRefuse: { await state.showUserMessage($0, lasting: .seconds(120)) }
            )
            Task { await watcher.onCapture { await pipeline.handle($0) } }
        }
        applyDoubleCopySetting()
    }

    func applyDoubleCopySetting() {
        let wanted = DoubleCopyPolicy.shouldObserveKeystrokes(
            enabled: AppDefaults.store.value(for: Setting.doubleCopyAppend),
            systemIntegrations: LaunchMode.current.usesSystemIntegrations
        )
        if wanted, doubleCopyMonitor == nil {
            installDoubleCopyMonitor()
        } else if wanted, let monitor = doubleCopyMonitor,
                  DoubleCopyPolicy.needsReinstall(
                      installedWhileTrusted: doubleCopyMonitorWasTrusted, trustedNow: AccessibilityAccess.isTrusted
                  )
        {
            NSEvent.removeMonitor(monitor)
            installDoubleCopyMonitor()
        } else if !wanted, let monitor = doubleCopyMonitor {
            NSEvent.removeMonitor(monitor)
            doubleCopyMonitor = nil
        }
    }

    func currentExclusionRules() -> ExclusionRules {
        ExclusionRules.fromSettings()
    }

    func applyIntegrationSettings() {
        applyDoubleCopySetting()
        applyScreenShareSetting()
        applyStatusItemVisibility()
        reviewLiveSettings()
    }

    func applyScreenShareSetting() {
        guard LaunchMode.current.usesSystemIntegrations else { return }
        let wanted = AppDefaults.store.value(for: Setting.screenSharingPrivacy)
        if wanted, !screenShareDetector.isRunning {
            screenShareDetector.onStateChange = { [weak self] isSharing in
                self?.appState.isScreenBeingShared = isSharing
            }
            screenShareDetector.start()
        } else if !wanted, screenShareDetector.isRunning {
            screenShareDetector.stop()
            appState.isScreenBeingShared = false
        }
    }

    private func installDoubleCopyMonitor() {
        // kVK_ANSI_C = 8. We listen globally (requires Accessibility permission already granted)
        // so we can detect ⌘C pressed twice in quick succession while the user is in another app.
        // The global monitor callback fires on an arbitrary thread; the coordinator is an actor, so it is called
        // from a task.
        let coordinator = appendCoordinator
        doubleCopyMonitorWasTrusted = AccessibilityAccess.isTrusted
        doubleCopyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard event.keyCode == 8, modifiers == .command else { return }
            Task { await coordinator.markCopy() }
        }
    }
}

/// What `reviewAllowances` remembers between looks.
@MainActor
final class AllowanceReview {
    var last: [String: Date] = [:]
    var timer: Timer?
}

extension AppDelegate {
    /// What a change in preferences must act on at once, not at the next time the shelf opens.
    @MainActor
    func reviewLiveSettings() {
        reviewAllowances()
        // Switching the history lock off must unlock now, or the menu-bar icon stays a lock until the next shelf.
        if appState.isHistoryLocked, !AppDefaults.store.value(for: Setting.biometricLockEnabled) {
            appState.checkAndApplyBiometricLock()
        }
    }

    /// A kept password-manager copy lives as long as the allowance that let it in (ADR 0004). Looks at which
    /// allowances ended since the last look, removes those apps' copies, and sets a timer for the next end.
    @MainActor
    func reviewAllowances() {
        let current = ExclusionAllowances().active()
        let ended = ExclusionAllowances.ended(from: allowanceReview.last, to: current)
        allowanceReview.last = current
        allowanceReview.timer?.invalidate()
        allowanceReview.timer = nil
        if let next = current.values.filter({ $0 < .distantFuture }).min() {
            let delay = max(next.timeIntervalSinceNow, 0) + 1
            allowanceReview.timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.reviewAllowances() }
            }
        }
        if !ended.isEmpty { removeKeptConcealedCopies(from: ended) }
    }

    /// Nil means every kept copy: no allowance survives a launch.
    func removeKeptConcealedCopies(from apps: Set<String>?) {
        guard let service = storageService else { return }
        Task {
            do {
                let removed = try await service.removeKeptConcealedCopies(from: apps)
                if removed > 0 { AutoBackupSettings().lowerBaseline(by: removed) }
            } catch {
                Self.logger.error("Removing kept copies failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Fetches the GIF behind a browser's Copy Image, under `LinkPreviewPolicy.mayFetchGIF` (ADR 0005).
    func makeRemoteGIFFetcher() -> @Sendable (URL) async -> Data? {
        { [appState] address in
            let locked = await MainActor.run { appState.isHistoryLockedNow() }
            guard LinkPreviewPolicy.mayFetchGIF(
                isEnabled: LinkPreviewPolicy.isEnabled(),
                isEligible: LinkPreviewEligibility.isEligible(address),
                isHistoryLocked: locked
            ) else { return nil }
            return await URLMetadataFetcher.downloadGIF(from: address)
        }
    }
}

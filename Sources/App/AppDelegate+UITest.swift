// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore

extension AppDelegate {
    /// A UI-test app is a regular app so XCUITest can see and drive its windows; Pesto proper is a
    /// menu-bar accessory.
    static var baseActivationPolicy: NSApplication.ActivationPolicy {
        LaunchMode.current == .uiTest ? .regular : .accessory
    }

    func presentQuickMenu(near cursorRect: NSRect) {
        guard !appState.isHistoryLockedNow() else { return showOverlay() }
        quickMenuController.show(
            near: cursorRect,
            onSelect: { [weak self] payloadKind in
                guard let self else { return }
                self.runPasteTask(.quickMenu) { delegate in
                    await delegate.appState.pasteCoordinator.executePaste(payload: payloadKind)
                }
            },
            onDismiss: {}
        )
    }

    /// Timestamps the termination callbacks in the command log, so a UI test can tell a slow app from a slow
    /// process reaper.
    func recordTermination(_ event: String) {
        guard LaunchMode.current == .uiTest else { return }
        UITestSupport.appendCommandLog("\(event) \(Date().timeIntervalSince1970)", in: AppPaths.supportDirectory)
    }

    func startUITestHarness() {
        // A spring's tail or a highlight that fades out makes a screenshot and an "exists" wait depend on frame timing;
        // a test that is about motion passes -UITestMotion.
        if !CommandLine.arguments.contains("-UITestMotion") { Motion.reduceMotionOverride = true }
        let configuration = RuntimeConfiguration.current
        showMarketingBackdropIfRequested()
        startUITestCommandPolling()
        let directory = AppPaths.supportDirectory
        // Seed only a fresh working directory: a relaunch within one test must see the persisted state.
        let previous = UITestSupport.readyMarker(in: directory)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(UITestSupport.readyFileName))
        Task { @MainActor in
            let seeded = if let previous { previous.seededCount } else { await seedForUITest(configuration.seed) }
            do {
                try UITestSupport.markReady(seededCount: seeded, in: directory)
            } catch {
                Self.logger.error("UI-test ready marker failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func seedForUITest(_ profile: SeedProfile) async -> Int {
        guard let service = storageService else { return 0 }
        let captures = SeedFixtures.captures(for: profile)
        var seeded = 0
        for (index, capture) in captures.enumerated() {
            do {
                let isSuggestionClip = profile == .suggestion && index == 0
                try await service.ingest(
                    capture,
                    preferredItemID: isSuggestionClip ? SeedFixtures.suggestionClipID : nil
                )
                seeded += 1
            } catch {
                Self.logger.error("UI-test seed ingest failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Pictures are judged after they are saved; a test must not start while a card is still covered.
        await service.waitForBackgroundWork()
        if profile == .marketing { await seedMarketingCollections() }
        if profile == .lunchRush { await seedLunchRush() }
        if profile == .suggestion {
            for daysAgo in (0..<SeedFixtures.suggestionPasteCount).reversed() {
                _ = try? await service.notePasted(
                    id: SeedFixtures.suggestionClipID, at: Date.now.addingTimeInterval(-Double(daysAgo) * 86_400)
                )
            }
        }
        return seeded
    }

    /// Polls the command queue the runner writes into the shared working directory.
    private func startUITestCommandPolling() {
        let directory = AppPaths.supportDirectory
        uiTestCommandTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                for command in UITestCommandQueue.drain(in: directory) {
                    UITestSupport.appendCommandLog("received \(command.rawValue)", in: directory)
                    self?.perform(command)
                }
            }
        }
    }

    private func perform(_ command: UITestCommand) {
        switch command {
        case .showOverlay: showOverlay()
        case .hideOverlay: hideOverlay()
        case .showQuickMenu: presentQuickMenu(near: NSRect(x: 600, y: 500, width: 2, height: 18))
        case .togglePinnedWindow: togglePinnedWindow()
        case .openSettings: openSettingsWindow()
        case .openSettingsAtData:
            appState.pendingSettingsSection = SettingsSection.data.rawValue
            openSettingsWindow()
        case .showOnboarding: showOnboarding()
        case .openAbout: openAboutWindow()
        case .toggleHideContents: statusToggleContentHidden()
        case .walkShelfToEnd: appState.uiTestWalkRequest += 1
        case .showToast: toastController.show(.manualPaste(.pressCommandV), holds: true)
        case .stackUserPaste: stackUserPasted()
        }
    }

    /// XCUITest hook: `--show-overlay` delays 1.5 s then opens the overlay so the
    /// pasteboard watcher has time to ingest content written by the test host.
    func scheduleTestOverlayIfNeeded() {
        guard CommandLine.arguments.contains("--show-overlay") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            self.showOverlay()
        }
    }
}

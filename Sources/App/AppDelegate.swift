// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import Sparkle
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AppDelegate")
    /// Dedicated logger for paste pathways. Stream with `make logs-paste`.
    /// Emits one `[start]` and one `[end]` per task, tagged with `source=` so
    /// phantom-paste reports can be traced to the trigger that fired them.
    nonisolated static let pasteLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "paste")
    let appState = AppState()
    private var appearanceObserver: Any?
    var systemThemeObserver: Any?
    var statusAppearanceObservers: [any NSObjectProtocol] = []
    var overlayWindowController: OverlayWindowController?
    /// SPUStandardUpdaterController must be retained on the delegate for the lifetime of the app.
    /// Lazy so only a normal launch starts the updater; `applicationDidFinishLaunching` touches it.
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: LaunchMode.current.usesSystemIntegrations && !BuildKind.isDevelopment,
        updaterDelegate: appState.updateReminders,
        userDriverDelegate: appState.updateReminders
    )
    var watcherTask: Task<Void, Never>?
    /// The paste in flight. Sleep, wake and screen lock interrupt it so a paste suspended across them cannot fire
    /// into whatever app is focused on return.
    let pasteTasks = PasteTaskTracker()
    var storageService: StorageService?
    var retentionPruner: RetentionPruner?
    private var retentionTimer: Timer?
    /// The allowances running when `reviewAllowances` last looked, and the timer that looks again as the next ends.
    let allowanceReview = AllowanceReview()
    private var lastRetentionPolicy: RetentionPolicy?
    let toastController = ToastWindowController()
    let stackHUDController = StackHUDWindowController()
    let fillInPrompt = FillInPromptWindowController()
    let stackSession = StackPasteSession()
    let aiResultController = AIResultPanelController()
    var onboardingWindow: NSWindow?
    let screenShareDetector = ScreenShareDetector()
    var screenLockClearing: ScreenLockClearing?
    let appendCoordinator = AppendModeCoordinator()
    var doubleCopyMonitor: Any?
    var doubleCopyMonitorWasTrusted = false
    var settingsWindowObserver: Any?
    /// Cancellable safety timer used in openSettingsWindow(). Cancelled when the window
    /// actually becomes key so the timer doesn't revert activation policy prematurely.
    var statusItem: NSStatusItem?
    /// The Edit menu's Undo and Redo, which the main menu keeps only a target to.
    var editMenuUndo: EditMenuUndo?
    /// Retains the manually-created Settings NSWindow so it is not deallocated after
    /// openSettingsWindow() returns. Cleared when the window closes.
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var uiTestCommandTimer: Timer?
    lazy var quickMenuController = QuickMenuWindowController(appState: appState)
    lazy var pinnedWindowController = PinnedWindowController(appState: appState)
    private lazy var urlSchemeHandler = AutomationURLHandler(host: self)

    func applicationWillFinishLaunching(_: Notification) {
        migrateLegacyIdentityIfNormalLaunch()
        ExceptionRecorder.installIfNormalLaunch()
        NSFWMode.migrateLegacySetting()
        AuthenticationWindowMigration.run()
        DefaultShortcutMigration.run()
        if LaunchMode.current.usesSystemIntegrations { SpotlightCleanup.removeIndexOnce() }
    }

    func applicationDidFinishLaunching(_: Notification) {
        let mode = LaunchMode.current
        NSApp.setActivationPolicy(Self.baseActivationPolicy)
        guard mode.bootsAppServices else { return }
        if mode.usesSystemIntegrations, offerToMoveToApplicationsIfNeeded() { return }
        QuickLookPreviewController.sweepStaleTempFiles()
        if mode.usesSystemIntegrations {
            _ = updaterController
            wireUpdateSettings()
        }
        bootStorage()
        resolveMissingEncryptionKey { [self] in finishLaunch(mode: mode) }
    }

    /// The rest of launch, once the history can be opened (`resolveMissingEncryptionKey`).
    private func finishLaunch(mode: LaunchMode) {
        appState.refreshImportOffer()
        runLaunchMigrations()
        runLaunchMaintenance()
        // Only warm up the Keychain key if it already exists. If it doesn't, we'll let
        // the user create it deliberately via OnboardingView so the "Allow access?" prompt
        // appears with the explicit "Set Up Encryption" affordance instead of unexpectedly
        // at launch. Once loaded, the key is cached in memory for the process lifetime
        // (see BlobEncryption.keyState), so no further Keychain reads happen for this run.
        if mode.usesSystemIntegrations, BlobEncryption.keyExists() {
            Task.detached(priority: .utility) {
                do {
                    _ = try BlobEncryption().loadOrCreateKey()
                } catch {
                    AppDelegate.logger
                        .error("Keychain key warm-up failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        startPasteboardWatcher()
        startAutoBackupIfNeeded()
        setupObservers()
        startPinnedHotkeyTracking()
        applyOnboardingGate()
        scheduleTestOverlayIfNeeded()
        applyScreenShareSetting()
        applyAppearance()
        applyAppIcon()
        setupStatusItem()
        if mode == .uiTest { startUITestHarness() }
    }

    /// Single consolidated UserDefaults observer: one run after a burst of writes ends (`DefaultsChangeObserver`),
    /// which
    /// re-applies appearance, retention and the integration switches (all idempotent), hands the watcher its exclusion
    /// rules and the storage actor its ingest rules.
    private func setupUserDefaultsObserver() {
        observeSystemTheme()
        appearanceObserver = DefaultsChangeObserver { [weak self] in
            guard let self else { return }
            applyAppearance()
            applyAppIcon()
            applyRetentionChange()
            applyIntegrationSettings()
            if let watcher = appState.pasteboardWatcher {
                await watcher.updateExclusionRules(currentExclusionRules())
            }
            if let service = storageService { await service.updateRules(ClipboardRules.fromUserDefaults()) }
        }
    }

    @MainActor
    private func applyAppearance() {
        let raw = AppDefaults.store.value(for: Setting.appearanceMode)
        let appearance: NSAppearance? = switch raw {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
        NSApp.appearance = appearance
        // Panels created before this point may have a stuck appearance set by
        // SwiftUI's preferredColorScheme — explicitly null them out so they
        // re-inherit from NSApp.
        // Not the status item's window: the menu bar's icon follows the menu bar (ADR 0013).
        for window in NSApp.windows
            where !MenuBarAppearance.isSystemChrome(windowClassName: String(describing: type(of: window)))
        {
            window.appearance = appearance
        }
        applyStatusItemAppearance()
        Self.logger.info("Applied appearance mode=\(raw, privacy: .public)")
    }

    /// The picked icon replaces the bundle icon in the Dock and the app switcher; Basil is the bundle icon itself.
    @MainActor
    private func applyAppIcon() {
        let choice = AppIconChoice(stored: AppDefaults.store.value(for: Setting.appIcon))
        NSApp.applicationIconImage = choice.dockImageName.flatMap { NSImage(named: $0) }
    }

    /// Removes what retention and a clip's own expiry say should go. Runs at launch, on the six-hour timer and when the
    /// policy changes, never when the shelf opens: the sweep reads every unpinned clip, and doing that on each show
    /// cost 78 ms of the 100 ms budget (P-01). A clip past its expiry is hidden from the shelf in the meantime.
    nonisolated static func sweepRetention(_ pruner: RetentionPruner) {
        Task {
            do {
                let removed = try await pruner.sweep()
                AutoBackupSettings().lowerBaseline(by: removed)
            } catch {
                logger.error("Retention sweep failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Lowering the retention setting should trim history now, not at the next six-hour sweep.
    private func applyRetentionChange() {
        let policy = RetentionPolicy.fromDefaults(AppDefaults.store)
        guard policy != lastRetentionPolicy else { return }
        lastRetentionPolicy = policy
        if let pruner = retentionPruner { Self.sweepRetention(pruner) }
    }

    /// Brings data from older versions up to date, one migration after another off the main actor (`LaunchMigrator`).
    private func runLaunchMigrations() {
        guard let service = storageService else { return }
        Task(priority: .utility) { await LaunchMigrator.run(LaunchMigration.standard(service: service)) }
    }

    private func bootStorage() {
        // Tier 1: the disk store (CloudKit-backed only when sync is available). Tier 2: the same store without sync.
        // Tier 3: in-memory (disk full or a schema conflict), so the history is lost on relaunch and the shelf says so.
        let cloudKitEnabled = SyncAvailability.isAvailable
        let boot = StorageBoot.run(
            openers: .init(
                synced: { try ModelContainerSetup.openSynced(cloudKitEnabled: cloudKitEnabled) },
                syncedLocalOnly: { try ModelContainerSetup.openSynced(cloudKitEnabled: false) },
                local: { try ModelContainerSetup.openLocal() },
                inMemory: { try ModelContainerSetup.makeInMemory().synced }
            ),
            cloudKitEnabled: cloudKitEnabled
        )
        appState.historyContainer = boot.synced
        appState.historyStore = boot.synced.map { HistoryStore(container: $0) }
        appState.localContainer = boot.local
        appState.storeIsOnDisk = boot.isOnDisk

        // Expose stable references for NSScriptCommand subclasses (NSApp.delegate cast fails
        // in SwiftUI @NSApplicationDelegateAdaptor apps, so we use a static bridge instead).
        ScriptingContext.modelContainer = appState.historyContainer
        ScriptingContext.appState = appState
        ScriptingContext.clearHistory = { [weak self] range in
            await MainActor.run { self?.requestClearHistory(range) }
        }
        ScriptingContext.openShelf = { [weak self] query in
            self?.showOverlay(from: .script)
            guard let query, !query.isEmpty else { return }
            self?.appState.searchText = query
            self?.appState.isSearchActive = true
        }
        ScriptingContext.setContentHidden = { [weak self] hidden in
            self?.appState.isContentHiddenManually = hidden
        }
        ScriptingContext.pasteItem = { [weak self] item in
            self?.executePasteItem(item)
        }
        appState.pasteInPlace = { [weak self] item in
            self?.executePasteItem(item)
        }
        appState.cancelActiveStack = { [weak self] in
            self?.cancelStack()
        }

        if let synced = appState.historyContainer {
            let service = StorageService(modelContainer: synced, environment: .live(
                rules: ClipboardRules.fromUserDefaults(),
                // A GIF a browser copied arrives as its first frame; the rest is fetched from where it came from, under
                // the Link Previews switch and with a link preview's checks on the address (ADR 0005).
                remoteGIFFetcher: makeRemoteGIFFetcher()
            ))
            storageService = service
            appState.storageService = service
            appState.startSimilarityWork()
            let store = StorageRetentionStore(service: service)
            let pruner = RetentionPruner(store: store) { RetentionPolicy.fromDefaults(AppDefaults.store) }
            retentionPruner = pruner
            lastRetentionPolicy = RetentionPolicy.fromDefaults(AppDefaults.store)
            Self.sweepRetention(pruner)
            retentionTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
                Self.sweepRetention(pruner)
            }
        }
    }

    private func setupObservers() {
        // React whenever the overlay is dismissed.
        // `AppState.close(_:)` says why the shelf closed: a chosen clip is pasted, a dismissal pastes nothing.
        appState.onOverlayHidden = { [weak self] in self?.handleOverlayHidden() }

        setupHotkeyHandlers()

        setupAccessibilityRefreshObserver()

        setupWorkspaceActivationObserver()

        screenLockClearing = ScreenLockClearing { [weak self] in
            guard let service = self?.storageService else { return }
            do {
                try await service.clearNonPinned(in: .all)
            } catch {
                Self.logger.error("Clear on lock failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Cancel any pending paste task when the Mac wakes from sleep or the screen unlocks.
        // Without this, a Task.sleep(300ms) suspended mid-paste resumes immediately on wake
        // and pastes into whatever text field the user is currently in.
        // didWakeNotification = hardware sleep/wake (lid open/close, power button).
        // screensDidWakeNotification = screen lock/unlock (CMD+CTRL+Q, screensaver, display sleep).
        // Going to sleep or dimming the screen interrupts too: a selection made just before is stale either way.
        for name in [
            NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification
        ] {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // A Mac that slept or locked its screen is not the person who just authenticated.
                AuthenticationGrace.shared.clear()
                Task { @MainActor [weak self] in
                    if self?.pasteTasks.isRunning == true {
                        Self.pasteLogger.notice("[cancel] reason=wake-or-screen-unlock")
                    }
                    self?.pasteTasks.interrupt()
                }
            }
        }

        setupUserDefaultsObserver()

        appState.onAILoading = { [weak self] in self?.aiResultController.showLoading() }
        appState.onAIResult = { [weak self] result in
            guard let self else { return }
            aiResultController.showResult(
                result,
                onClose: { [weak self] in
                    self?.appState.aiResult = nil
                    self?.aiResultController.hide()
                },
                onPaste: { [weak self] in self?.pasteAIResult(result) },
                onCopy: { [weak self] in self?.appState.copyAIResult(result) },
                onReadNext: { [weak self] in self?.appState.readNextAIPart() },
                onCancelPart: { [weak self] in self?.appState.cancelAIPart() },
                onCombine: { [weak self] in self?.appState.combineAIParts() }
            )
        }
        appState.onAIResultCleared = { [weak self] in self?.aiResultController.hide() }
    }

    private func setupHotkeyHandlers() {
        appState.hotkeyController.onOpenOverlay = { [weak self] in
            await MainActor.run { self?.toggleOverlay(from: .hotkey) }
        }
        appState.hotkeyController.onQuickPasteLast = { [weak self] in
            await MainActor.run { self?.triggerQuickPasteLast() }
        }
        appState.hotkeyController.onPastePlainText = { [weak self] in
            await MainActor.run { self?.triggerPastePlainText() }
        }
        appState.hotkeyController.onTogglePinnedWindow = { [weak self] in
            await MainActor.run { self?.statusTogglePinned() }
        }
        appState.hotkeyController.onToggleCapture = { [weak self] in
            await MainActor.run { self?.statusToggleCapture() }
        }
        appState.hotkeyController.onToggleClipContents = { [weak self] in
            await MainActor.run { self?.statusToggleContentHidden() }
        }
        appState.hotkeyController.onPinnedHotkey = { [weak self] slot in
            self?.triggerPinnedHotkey(slot: slot)
        }
        // Global hotkeys are machine-wide; a UI-test run drives the app through UITestCommand instead.
        if LaunchMode.current.usesSystemIntegrations { appState.hotkeyController.register() }

        appState.onboardingCompleted = { [weak self] in
            self?.seedFirstRunSamples()
            self?.appState.refreshImportOffer()
        }
        appState.resumeCapturing = { [weak self] in
            guard let self, appState.isCapturingPaused else { return }
            Task { await self.toggleCapture() }
        }
        appState.openAbout = { [weak self] in self?.openAboutWindow() }
        appState.showWelcome = { [weak self] in self?.showOnboarding() }
        appState.exportCollection = { [weak self] id in self?.requestCollectionExport(id: id) }
        appState.openFloatingWindowFromOverlay = { [weak self] in
            guard let self else { return }
            self.appState.close(.afterHide { [weak self] in
                guard self?.appState.isPinnedWindowVisible == false else { return }
                self?.togglePinnedWindow()
            })
        }
        appState.showToast = { [weak self] toast in self?.toastController.show(toast) }
        appState.askFillIns = { [weak self] title, fields, initial in
            await self?.fillInPrompt.ask(title: title, fields: fields, initial: initial)
        }
        appState.openSettingsFromOverlay = { [weak self] in
            guard let self else { return }
            self.appState.close(.afterHide { [weak self] in self?.openSettingsWindow() })
        }

        NotificationCenter.default.addObserver(
            forName: .hotkeySettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.hotkeyController.reregisterMain()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // Menu-bar accessory app: closing Settings or onboarding must not quit Pesto. The SwiftUI
        // lifecycle consults this and otherwise terminates once its last regular window closes.
        false
    }

    /// Clearing on quit is asynchronous, so quitting is deferred until it finishes. (It used to block the main
    /// thread on a semaphore for a Task that needed the main thread, so it never cleared and just hung.)
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        recordTermination("shouldTerminate")
        guard LaunchMode.current.bootsAppServices,
              ClearOnQuitPolicy.shouldClear(
                  enabled: AppDefaults.store.value(for: Setting.clearOnQuit), hasStorage: storageService != nil,
                  keyUnresolved: appState.isEncryptionKeyUnresolved
              ),
              let service = storageService else { return .terminateNow }
        Task { @MainActor in
            do {
                try await service.clearNonPinned(in: .all)
            } catch {
                Self.logger.error("clearOnQuit deletion failed: \(error.localizedDescription, privacy: .public)")
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_: Notification) {
        recordTermination("willTerminate")
        guard LaunchMode.current.bootsAppServices else { return }
        watcherTask?.cancel()
        retentionTimer?.invalidate()
        appState.hotkeyController.unregister()
    }

    func toggleCapture() async {
        guard let watcher = appState.pasteboardWatcher else { return }
        await watcher.togglePause()
        appState.isCapturingPaused = await watcher.isPaused
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "pesto" {
            urlSchemeHandler.handle(url)
        }
    }

    func togglePinnedWindow() {
        pinnedWindowController.toggle()
    }

    func toggleOverlay(from source: ShelfOpenSource = .internalRoute) {
        // A stack pasted with ⌘V is ended by opening the shelf; without Accessibility ⌘⇧V pastes its next clip.
        if appState.activeStack != nil {
            guard stackSession.isWatching else { return pasteNextStackItem() }
            cancelStack()
        }
        if appState.isOverlayVisible {
            hideOverlay()
        } else {
            showOverlay(from: source)
        }
    }

    func showOverlay(from source: ShelfOpenSource = .internalRoute) {
        // Ensure we're in .accessory mode before capturing focus, unless a regular Pesto
        // window (such as Settings) is currently visible — demoting to .accessory while
        // Settings is key forces macOS to activate the previous app, which immediately
        // fires didActivateApplicationNotification and closes the shelf.
        let hasVisibleRegularWindow = [settingsWindow, onboardingWindow, aboutWindow].contains {
            $0?.isVisible == true
        }
        if !hasVisibleRegularWindow {
            NSApp.setActivationPolicy(Self.baseActivationPolicy)
        }
        // Capture the frontmost app NOW, before the overlay steals focus.
        appState.pasteCoordinator.focusRestoration.capture()
        let frontmost = NSWorkspace.shared.frontmostApplication
        recordFrontmostApp(frontmost)

        // If the user has a focused text field in another app, show the compact quick menu at the cursor.
        // The quick menu shows history at the caret, so a locked history opens the lock screen instead.
        appState.checkAndApplyBiometricLock()
        if source.allowsQuickMenu, LaunchMode.current.usesSystemIntegrations,
           AppDefaults.store.value(for: Setting.opensQuickMenuAtCursor),
           !appState.isHistoryLocked, frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier,
           let pid = frontmost?.processIdentifier,
           let cursorRect = CursorPositionDetector.cursorRect(for: pid)
        {
            presentQuickMenu(near: cursorRect)
            return
        }

        if overlayWindowController == nil {
            let controller = OverlayWindowController(appState: appState)
            controller.onClickOutside = { [weak self] in self?.hideOverlay() }
            overlayWindowController = controller
        }
        overlayWindowController?.show()
        appState.isOverlayVisible = true
        appState.checkAndApplyBiometricLock()
        appState.shelfDidOpen()
    }

    /// Closes the overlay without pasting (Escape / hotkey toggle path); any paste that was waiting is dropped.
    func hideOverlay() {
        appState.appChipFilter = []
        appState.close()
    }
}

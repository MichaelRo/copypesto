// SPDX-License-Identifier: MIT
import AppKit
import Observation
import os
import PestoCore
import SwiftData
import SwiftUI

/// Central observable state object threaded through the view hierarchy.
@MainActor
@Observable
final class AppState {
    var isOverlayVisible = false {
        didSet {
            historyStore?.setVisible(isOverlayVisible || isPinnedWindowVisible)
            if !isOverlayVisible {
                // A pointer that was on a banner when the shelf closed never reports leaving it.
                dismissUndoOffer()
                releaseUserError()
                onOverlayHidden?()
            }
        }
    }

    /// The history both surfaces read. Set once storage is up.
    @ObservationIgnored var historyStore: HistoryStore?

    /// Called whenever the shelf is set to hidden. Wired by AppDelegate; `takePendingExit()` says why it
    /// closed (`ShelfExit`): a chosen clip is pasted, a dismissal pastes nothing.
    @ObservationIgnored var onOverlayHidden: (() -> Void)?

    /// Restores key focus to the shelf panel (e.g. after Quick Look closes).
    @ObservationIgnored var onRestoreKeyFocus: (() -> Void)?
    private(set) var lastUserError: String?
    @ObservationIgnored private var userErrorDismissal: Task<Void, Never>?
    /// The banner that offers to take back what was just deleted. Set by `offerUndo()`, gone after a while.
    var undoOffer: UndoLabel?
    @ObservationIgnored var undoOfferDismissal: Task<Void, Never>?
    /// Counts the undos and redos that were applied, so the shelf filters again (a clip moved in or out of a
    /// collection).
    var undoGeneration = 0
    /// `true` while the pinned floating window is on screen.
    var isPinnedWindowVisible = false {
        didSet { historyStore?.setVisible(isOverlayVisible || isPinnedWindowVisible) }
    }

    /// `true` while the system Quick Look panel is open over the shelf.
    var isQuickLookOpen = false

    /// `true` when biometric lock is active — grid is blurred until Touch ID succeeds.
    var isHistoryLocked = false
    /// Whether this Mac can ask for Touch ID or a password. Refreshed at launch, every 15 s by the lock watchdog and
    /// when Settings opens, so a view never calls LocalAuthentication itself.
    private(set) var authenticationAvailability = AuthenticationAvailability.available
    @ObservationIgnored private var lastBiometricUnlock: Date?
    @ObservationIgnored private var lockWatchdog: Task<Void, Never>?
    @ObservationIgnored var similarityTask: Task<Void, Never>?
    @ObservationIgnored static let similarityLogger = Logger(
        subsystem: AppIdentity.logSubsystem,
        category: "Similarity"
    )
    /// The Touch ID request the shelf is showing, if any (`AppState+ShelfAuthentication.swift`).
    var shelfAuthentication: ShelfAuthenticationRequest?
    @ObservationIgnored var decodePopoverKeys: DecodePopoverKeys?
    @ObservationIgnored var shelfAuthenticationContinuation: CheckedContinuation<Bool, Never>?
    /// How many system authentication dialogs (the password) are up for something the shelf asked for.
    @ObservationIgnored var systemAuthenticationDialogs = 0
    var searchText = ""
    /// `true` when the search field is visible and active in the CommandBar.
    /// Written by the keyboard monitor (type-to-search) and by the CommandBar itself.
    var isSearchActive = false
    var selectedCollectionID: UUID?
    var hasAccessibilityPermission = false
    /// The app chips switched on; a clip from any of them stays. Cleared when the shelf closes.
    var appChipFilter: Set<String> = []
    @ObservationIgnored var frontmostAppBundleID: String?
    @ObservationIgnored var frontmostAppName: String?
    var isScreenBeingShared = false
    /// Hide Contents Now: set from the menu-bar item, the Hide Clip Contents intent or a Focus filter.
    var isContentHiddenManually = false

    func isContentCovered(screenSharingPrivacy: Bool) -> Bool {
        ContentCover.isCovered(
            manual: isContentHiddenManually, settingOn: screenSharingPrivacy, shareDetected: isScreenBeingShared
        )
    }

    /// `true` while the user is dragging a card out of the overlay.
    /// Guards the click-outside handler so an in-progress drag does not dismiss the panel.
    var isDragging = false
    /// UUID of the clipboard item currently being dragged within the overlay.
    /// Set on drag-start, cleared on drag-end. Used by collection chip drop handlers
    /// to identify the item without relying on custom UTType registration.
    var draggingItemID: UUID? {
        didSet { if draggingItemID != nil { onClipDragStarted?() } }
    }

    /// Set by the shelf's window controller: a clip drag began, so the shelf gets out of its way.
    @ObservationIgnored var onClipDragStarted: (() -> Void)?
    /// UUID of the pinboard collection chip currently being dragged horizontally to reorder.
    var draggingPinboardID: UUID?

    /// `true` while the inline collection name editor in CommandBarView is active.
    /// Gates the global key monitor so typing routes to the editor, not search.
    var isEditingCollection = false

    /// Set to open the inline collection creator. Lives here (not as `@State` in
    /// CommandBarView) so ⌘N from the grid's key coordinator can trigger it too.
    var isCreatingCollection = false

    /// Mirrors `PasteboardWatcher.isPaused`. Toggled via the menu bar; the menu bar reads
    /// this to show the current state without crossing an actor boundary on every render.
    var isCapturingPaused = false

    // MARK: - Search filters (active only while isSearchActive == true)

    typealias SearchDateFilter = PestoCore.SearchDateFilter

    /// Clipboard types selected by the filter bar chips. Empty = all types shown.
    var searchTypeFilter: Set<String> = []
    /// Date range selected in the filter bar. `.all` = no date constraint.
    var searchDateFilter: SearchDateFilter = .all
    /// Source app bundle IDs selected in the filter bar. Empty = all sources shown.
    var searchSourceFilter: Set<String> = []
    /// Per-session opt-in to surface NSFW-flagged items in search results. Reset on
    /// search deactivation so the user is never surprised by hidden content next time.
    var showHiddenNSFW = false
    /// Filter bar "Sensitive" chip: show only clips marked sensitive, including ones the shelf otherwise hides.
    var searchSensitiveOnly = false
    /// Filter bar "Other Devices" chip: show only clips copied on another device.
    var searchRemoteOnly = false
    /// Where Tab has the keyboard in the filter bar (`FilterChipCursor`); nil is the search field.
    var filterChipCursor: Int?
    /// The chips on screen, in order, as the keyboard can act on them. Set by the command bar.
    @ObservationIgnored var filterChipActions: [FilterChipAction] = []

    func clearSearchFilters() {
        searchTypeFilter = []
        searchDateFilter = .all
        searchSourceFilter = []
        showHiddenNSFW = false
        searchSensitiveOnly = false
        searchRemoteOnly = false
    }

    let hotkeyController = HotkeyController()
    let pasteCoordinator = PasteCoordinator()

    /// Set by AppDelegate after containers are initialized.
    @ObservationIgnored var historyContainer: ModelContainer?
    /// The single writer for deleting and clearing history. Set once storage is up.
    @ObservationIgnored var storageService: StorageService?
    @ObservationIgnored var localContainer: ModelContainer?
    /// The version of a scheduled update Sparkle found while nobody was looking (shown in the status menu).
    @ObservationIgnored var availableUpdateVersion: String?
    /// Sparkle holds its user-driver delegate weakly, so the app state keeps this one.
    @ObservationIgnored lazy var updateReminders = UpdateReminders(appState: self)
    /// True while the key-missing dialog is up or ended in Quit: quitting must not run Clear on Quit then.
    @ObservationIgnored var isEncryptionKeyUnresolved = false
    /// False when storage fell back to memory: nothing of this session survives a quit, and no backup may be written.
    @ObservationIgnored var storeIsOnDisk = true
    /// How long a pasted secret stays on the pasteboard if nothing else is copied; a test shortens it.
    @ObservationIgnored var secretClearDelay: Duration = .seconds(30)
    @ObservationIgnored var secretClearTask: Task<Void, Never>?
    var pendingSettingsSection: String?
    /// Bumped by the `walkShelfToEnd` UI-test command; the grid walks its focus to the last clip.
    var uiTestWalkRequest = 0
    /// The lost-key recovery window and its delegate, kept alive while it is on screen.
    @ObservationIgnored var keyRecoveryWindow: (NSWindow, KeyRecoveryWindowCloser)?
    /// The installed apps the shelf offers to import from, until the person answers; empty when there is no offer.
    var importOffer: [ImportSource] = []
    /// The clipboard managers found installed, for the Found on this Mac card in Settings. Filled by
    /// `refreshInstalledImportSources()`: a view's own `.task` never ran for the empty card.
    var installedImportSources: [ImportSource] = []
    /// A Settings row to scroll to and flash once the pane is showing (the banner's Choose… takes the person there).
    var pendingSettingsRow: String?
    /// What each app's import brought in during this session; not remembered, because a newer library can be imported
    /// tomorrow and a stored flag would then be wrong.
    var importedThisSession: [ImportSource: Int] = [:]
    /// Set when the offer is accepted; Settings, Data starts that import once it is showing.
    var pendingImportSource: ImportSource?
    var pendingSnippetSeed: UUID?
    var shelfSuggestion: ShelfSuggestionPresentation?
    @ObservationIgnored var shelfSuggestionFacts: ShelfSuggestionFacts?
    @ObservationIgnored var shelfPasteTally: [UUID: Int] = [:]
    @ObservationIgnored var shelfFactsProvider: (@Sendable () async -> ShelfSuggestionFacts?)?
    @ObservationIgnored var shelfSuggestionDwellTask: Task<Void, Never>?
    @ObservationIgnored var clipboardAppDetector: any ClipboardAppDetecting = ClipboardAppDetection.forThisLaunch()
    /// Reads and sets whether Sparkle checks for updates by itself. Set when the updater runs (a normal launch), so
    /// Settings offers the switch only where it does something.
    @ObservationIgnored var automaticUpdateChecks: (get: () -> Bool, set: (Bool) -> Void)?
    /// ⌃N slots already warned about, so a refresh does not repeat the banner.
    @ObservationIgnored var warnedHotkeySlots: Set<Int> = []
    @ObservationIgnored var pasteboardWatcher: PasteboardWatcher?
    @ObservationIgnored var clipboardBeforeLastItemWrite = ""
    let ownWrites = OwnWriteGate()

    func attempt(_ failureMessage: String.LocalizationValue, _ body: () throws -> Void) {
        do { try body() } catch { report(String(localized: failureMessage), error: error) }
    }

    func attempt(_ failureMessage: String.LocalizationValue, _ body: () async throws -> Void) async {
        do { try await body() } catch { report(String(localized: failureMessage), error: error) }
    }

    func dismissUserError() {
        userErrorDismissal?.cancel()
        lastUserError = nil
    }

    private func report(_ message: String, error: any Error) {
        Logger(subsystem: AppIdentity.logSubsystem, category: "UserError")
            .error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        showUserMessage(message)
    }

    /// Shows a message in the shelf's banner and speaks it, for a problem the person should know about that is not a
    /// failed action.
    /// `lasting` keeps a message for a person who was not looking when it happened (a copy that was refused while the
    /// shelf was closed); the default is long enough to read.
    func showUserMessage(_ message: String, lasting: Duration? = nil) {
        lastUserError = message
        Announcer.announce(message, priority: .high)
        scheduleUserErrorDismissal(after: lasting ?? Self.defaultUserMessageDuration)
    }

    /// Long enough to read a sentence, and longer while VoiceOver is speaking it (WCAG 2.2.1).
    static var defaultUserMessageDuration: Duration {
        .seconds(NSWorkspace.shared.isVoiceOverEnabled ? 20 : 10)
    }

    private func scheduleUserErrorDismissal(after duration: Duration) {
        userErrorDismissal?.cancel()
        userErrorDismissal = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.lastUserError = nil
        }
    }

    /// The pointer is on the banner: it stays while it is being read.
    func holdUserError() {
        userErrorDismissal?.cancel()
        userErrorDismissal = nil
    }

    /// The pointer left: the banner goes after a short grace, not at once.
    func releaseUserError(after grace: Duration = .seconds(4)) {
        guard lastUserError != nil else { return }
        scheduleUserErrorDismissal(after: grace)
    }

    @discardableResult
    func writeToPasteboard<Result>(_ body: (NSPasteboard) -> Result) -> Result {
        ownWrites.write(to: AppPasteboard.general, body)
    }

    /// Why the shelf is closing, set by `close(_:)` and taken once by `AppDelegate.handleOverlayHidden()`.
    @ObservationIgnored private var pendingExit: ShelfExit?

    /// Closes the shelf for a reason. Everything that closes it goes through here, so the hide handler always knows
    /// whether to paste, run something or do nothing. Closing a shelf that is already closed with nothing to do is a
    /// no-op: `isOverlayVisible`'s `didSet` runs the hide handler on every assignment of `false`, and a second run
    /// would clear an exit that was about to be used.
    func close(_ exit: ShelfExit = .dismissed) {
        guard isOverlayVisible || exit.actsWhenAlreadyClosed else { return }
        shelfDidClose()
        pendingExit = exit
        isOverlayVisible = false
    }

    /// The reason for the close that is being handled; a close that left none was a dismissal.
    func takePendingExit() -> ShelfExit {
        defer { pendingExit = nil }
        return pendingExit ?? .dismissed
    }

    /// Called when the user taps the Settings gear button inside the overlay.
    /// Wired by AppDelegate to hide the overlay then open the Settings window.
    @ObservationIgnored var openSettingsFromOverlay: (@MainActor () -> Void)?
    /// Shows the fill-in prompt for a snippet and answers nil when it is cancelled (set by the delegate).
    @ObservationIgnored var askFillIns: (@MainActor (String, [SnippetField], SnippetFills) async -> SnippetFills?)?
    /// Floats a notice that does not need the shelf (set by the delegate).
    @ObservationIgnored var showToast: (@MainActor (StatusToast) -> Void)?
    @ObservationIgnored var openFloatingWindowFromOverlay: (@MainActor () -> Void)?
    /// Exports a collection to a file the person chooses; closes the shelf first when it is open. Set by the delegate.
    @ObservationIgnored var exportCollection: (@MainActor (UUID) -> Void)?
    @ObservationIgnored var resumeCapturing: (@MainActor () -> Void)?
    /// Opens the About window; set by the app delegate. Settings' General pane has the button for it.
    @ObservationIgnored var openAbout: (@MainActor () -> Void)?
    @ObservationIgnored var showWelcome: (@MainActor () -> Void)?
    /// Asks Sparkle to check now; nil where there is no updater (tests, a build without one).
    @ObservationIgnored var checkForUpdates: (@MainActor () -> Void)?
    /// Pastes a clip without touching the shelf (the floating window's tap); set by the app delegate.
    @ObservationIgnored var pasteInPlace: (@MainActor (ClipboardItem) -> Void)?
    @ObservationIgnored var onboardingCompleted: (@MainActor () -> Void)?
    /// Set by the app delegate once storage is up; the privacy pane reads and clears through these.
    @ObservationIgnored var privacySnapshot: (@MainActor () async -> PrivacySnapshot?)?
    @ObservationIgnored var clearEverything: (@MainActor () async throws -> Int)?
    /// The tag and app chips of the command bar, counted on the storage actor.
    @ObservationIgnored var commandBarSuggestions: (@MainActor () async -> CommandBarSuggestions?)?

    // Action to run in the hide(completion:) block after the overlay panel finishes its
    // exit animation. Used by the Settings button so it fires only after the overlay is gone.

    /// Non-nil while a multi-item paste stack is active.
    /// `⌘⇧V` advances through items instead of opening the overlay.
    var activeStack: PasteStack?
    @ObservationIgnored var cancelActiveStack: (() -> Void)?

    // MARK: - AI actions

    @ObservationIgnored var aiCoordinator = AIActionCoordinator()
    var aiResult: AIResult? {
        didSet {
            if let aiResult {
                onAIResult?(aiResult)
            } else {
                // The panel closed, or the history locked: what was left of a long text is dropped with it.
                aiRun = nil
                aiPartTask?.cancel()
                aiPartTask = nil
                onAIResultCleared?()
            }
        }
    }

    /// The long text being summarized a part at a time (`AppState+AIParts`); in memory only while the panel is open.
    @ObservationIgnored var aiRun: AIRun?
    @ObservationIgnored var aiPartTask: Task<Void, Never>?
    @ObservationIgnored var onAIResultCleared: (() -> Void)?

    var aiIsLoading = false {
        didSet { if aiIsLoading { onAILoading?() } }
    }

    @ObservationIgnored var onAIResult: ((AIResult) -> Void)?
    @ObservationIgnored var onAILoading: (() -> Void)?

    /// Describes an image with the on-device model. Needs no key and sends nothing off this Mac.
    func runImageDescription(_ imageData: Data) {
        aiIsLoading = true
        Task {
            let result = await aiCoordinator.describeImage(imageData)
            aiResult = result
            AIResultAnnouncement.announce(result)
            aiIsLoading = false
        }
    }

    /// Runs an AI action on the given text with the on-device model.
    /// Result is published via `aiResult`; errors, including "Apple Intelligence is off", surface as `isError`.
    func runAIAction(
        _ action: AIAction, text: String, totalCharacters: Int? = nil, isProtected: Bool = false,
        sourceItemID: UUID? = nil, fullLength: Int? = nil
    ) {
        aiIsLoading = true
        Task {
            if let parts = aiCoordinator.parts(
                action: action, text: text, totalCharacters: totalCharacters, fullLength: fullLength
            ) {
                return await startPartsRun(
                    action: action, text: text, parts: parts, isProtected: isProtected, sourceItemID: sourceItemID
                )
            }
            let result = await aiCoordinator.run(action: action, text: text, totalCharacters: totalCharacters)
                .protecting(isProtected).madeFrom(sourceItemID)
            aiResult = result
            AIResultAnnouncement.announce(result)
            aiIsLoading = false
        }
    }

    init() {
        if RuntimeConfiguration.current.mode == .uiTest, RuntimeConfiguration.current.aiFixture {
            aiCoordinator = AIActionCoordinator(
                availability: { .available },
                complete: { _, message in "Summary: " + message.prefix(24) },
                budget: { 300 }
            )
        }
        hasAccessibilityPermission = AccessibilityAccess.isTrusted
        authenticationAvailability = UserAuthenticator.current.availability
    }

    /// Observation notifies on every assignment, equal value or not, and this runs on a timer while the shelf is
    /// open: only a change may be assigned.
    func recheckAccessibility() {
        let trusted = AccessibilityAccess.isTrusted
        if trusted != hasAccessibilityPermission { hasAccessibilityPermission = trusted }
    }

    // MARK: - Biometric lock

    /// Locks the history if the lock is enabled and the idle timeout has elapsed.
    /// Call when the overlay or floating window is shown.
    func checkAndApplyBiometricLock() {
        isHistoryLocked = HistoryLockPolicy.isLocked(
            enabled: AppDefaults.store.value(for: Setting.biometricLockEnabled),
            timeoutMinutes: AuthenticationGrace.minutes(),
            lastUnlock: HistoryLockPolicy.effectiveLastUnlock(
                lastBiometricUnlock,
                switchedOnAt: AppDefaults.store.object(forKey: HistoryLockPolicy.switchedOnKey) as? Date
            ),
            now: .now
        )
        // Decrypted previews must not outlive the lock, and neither may what could be undone.
        if isHistoryLocked {
            clipboardBeforeLastItemWrite = ""
            storageService?.undoHistory.clear()
            stopSimilarityWork()
            dismissUndoOffer()
            suppressShelfSuggestions()
            PreviewTextCache.shared.clear()
            historyStore?.dropSearchText()
            ThumbnailCache.shared.clear()
            LinkPreviewCache.shared.clear()
            AuthenticationGrace.shared.clear()
            QuickLookPreviewController.sweepStaleTempFiles()
        }
    }

    /// Refreshes the lock and reports it. Every entry point that reveals or pastes history asks this first.
    func isHistoryLockedNow() -> Bool {
        checkAndApplyBiometricLock()
        return isHistoryLocked
    }

    /// Unlocks only if the user authenticates; with nothing able to authenticate, history stays locked.
    func performBiometricUnlock() async {
        let unlocked = await withSystemAuthenticationDialog {
            await HistoryLockPolicy.unlock(using: UserAuthenticator.current)
        }
        guard unlocked else { return }
        completeUnlock()
    }

    func completeUnlock(at date: Date = Date()) {
        AuthenticationGrace.shared.record()
        let wasLocked = isHistoryLocked
        isHistoryLocked = false
        lastBiometricUnlock = date
        if wasLocked { startSimilarityWork() }
    }

    /// Immediately locks history and purges decrypted previews from memory.
    func lockHistory() {
        guard AppDefaults.store.value(for: Setting.biometricLockEnabled) else { return }
        lastBiometricUnlock = nil
        isHistoryLocked = true
        clipboardBeforeLastItemWrite = ""
        aiResult = nil
        storageService?.undoHistory.clear()
        stopSimilarityWork()
        dismissUndoOffer()
        suppressShelfSuggestions()
        PreviewTextCache.shared.clear()
        historyStore?.dropSearchText()
        ThumbnailCache.shared.clear()
        AuthenticationGrace.shared.clear()
        QuickLookPreviewController.sweepStaleTempFiles()
    }

    /// Locks an unlocked history whose idle timeout has passed. Surfaces that stay on screen (the floating window,
    /// Settings) never ask on their own, so a timer calls this.
    /// `canAuthenticate()` is a synchronous call to the Local Authentication daemon (about 15 ms, unbounded if the
    /// daemon is busy), so the main thread never makes it after launch.
    func refreshAuthenticationAvailability(using authenticator: any UserAuthenticating = UserAuthenticator
        .current) async
    {
        let current = await Task.detached(priority: .utility) { authenticator.availability }.value
        if current != authenticationAvailability { authenticationAvailability = current }
    }

    func relockIfIdle() {
        guard !isHistoryLocked, AppDefaults.store.value(for: Setting.biometricLockEnabled) else { return }
        checkAndApplyBiometricLock()
    }

    func startLockWatchdog() {
        guard lockWatchdog == nil, LaunchMode.current.usesSystemIntegrations else { return }
        lockWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.refreshAuthenticationAvailability()
                self?.relockIfIdle()
            }
        }
    }

    var asShelfActions: ShelfActionDispatcher {
        ShelfActionDispatcher(
            writeItem: { [weak self] item in self?.writeItem(item) },
            writeText: { [weak self] text, protected in self?.writeText(text, protected: protected) },
            authenticateInShelf: { [weak self] reason, auth, embedded, grace in
                guard let self else { return false }
                return await self.authenticateInShelf(
                    reason: reason, authenticator: auth, embeddedAvailable: embedded, grace: grace
                )
            },
            performBiometricUnlock: { [weak self] in
                await self?.performBiometricUnlock()
            },
            finishShelfAuthentication: { [weak self] success in
                self?.finishShelfAuthentication(success: success)
            },
            checkForUpdates: { [weak self] in
                self?.checkForUpdates?()
            },
            showWelcome: { [weak self] in
                self?.showWelcome?()
            },
            refreshAuthentication: { [weak self] in
                await self?.refreshAuthenticationAvailability()
            }
        )
    }
}

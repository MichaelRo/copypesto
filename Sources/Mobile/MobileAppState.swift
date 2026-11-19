// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore
import SwiftData
import UIKit

/// What the iPhone and iPad app holds for its views: the opened store and the services on it (ADR 0046).
@MainActor
@Observable
final class MobileAppState {
    struct Notice: Equatable {
        let text: String
        let isProblem: Bool
    }

    private(set) var historyContainer: ModelContainer?
    private(set) var historyStore: HistoryStore?
    private(set) var storageService: StorageService?
    /// False when the disk store would not open and the history lives in memory until the app quits.
    private(set) var storeIsOnDisk = false
    private(set) var hasBooted = false
    /// The last thing done or refused, shown as a banner for a few seconds.
    var notice: Notice?
    /// The newest action Undo can take back, offered in a banner after a delete (ADR 0008).
    var undoOffer: UndoLabel?
    /// The clipboard's change count offered as "Add what you copied" (`MobileAppState+ClipboardOffer.swift`).
    var clipboardOfferCount: Int?
    /// Counts saved text edits; the grid reads it to draw an edited card again (`MobileAppState+TextEdit.swift`).
    var textEdits = 0
    /// Sync with the person's other devices, once the history is open (`MobileAppState+Sync.swift`).
    var sync: MobileSync?
    let secretReveal: SecretReveal
    let historyLock: MobileHistoryLock
    /// A widget link that arrived while the history was locked, opened once it is unlocked.
    @ObservationIgnored var heldLink: URL?
    /// The launch migrations, so a test can wait for them before it removes its store.
    @ObservationIgnored private(set) var launchWork: Task<Void, Never>?
    @ObservationIgnored var noticeDismissal: Task<Void, Never>?
    @ObservationIgnored var undoOfferDismissal: Task<Void, Never>?
    /// The running pass over the share extension's inbox (`MobileAppState+Inbox.swift`), so two never overlap.
    @ObservationIgnored var inboxDrain: Task<InboxDrain.Report?, Never>?
    /// Where the AutoFill set is kept (`MobileAppState+QuickInsert.swift`); nil in a hosted test until it names one.
    @ObservationIgnored var quickInsert: QuickInsertTarget? = .current
    @ObservationIgnored var quickInsertRewrite: Task<Void, Never>?
    @ObservationIgnored var quickInsertObserver: (any NSObjectProtocol)?
    /// The last clip a widget link copied, so the library shows it (`MobileAppState+WidgetLink.swift`).
    var linkedClip: LinkedClip?
    /// Hands a link clip's web address to the browser; a test records it instead.
    @ObservationIgnored var openExternally: @MainActor (URL) -> Void = { UIApplication.shared.open($0) }
    /// Where the widget's snapshot is kept (`MobileAppState+Widget.swift`); nil in a hosted test until it names one.
    @ObservationIgnored var widget: WidgetTarget? = .current
    @ObservationIgnored var backgroundWork = BackgroundWork.system
    @ObservationIgnored var linkPreviewLoader = LinkPreviewLoader()
    /// The first-run welcome is up (`MobileAppState+Welcome.swift`).
    var showsWelcome = false
    /// The welcome's Turn On Sync asked the library to open the sync flow once the welcome has gone.
    @ObservationIgnored var syncSetUpRequested = false
    @ObservationIgnored var welcomeAgainRequested = false
    /// The one-time AutoFill tip is on screen (`MobileAppState+AutoFillTip.swift`).
    var offersAutoFillTip = false
    @ObservationIgnored var opensAutoFillSettings: @MainActor () async -> Void = AutoFillSettings.open
    /// What Decode JWT read, shown in a sheet; memory only, gone with the lock, a clear and leaving the foreground.
    var decodedJWT: JWTDecodeResult?
    /// An AI action's answer, shown in a sheet while `showsAI` (`MobileAppState+AI.swift`); memory only.
    var aiResult: AIResult?
    var aiIsLoading = false
    var showsAI = false
    @ObservationIgnored var aiCoordinator = MobileAppState.makeAICoordinator()
    /// What the menus ask before offering an action; a test names its own.
    @ObservationIgnored var aiAvailability: @Sendable () -> AIAvailability = MobileAppState.makeAIAvailability()
    @ObservationIgnored var aiSupportsVision: @Sendable () -> Bool = { AppleIntelligenceClient.supportsVision }
    @ObservationIgnored var aiTask: Task<Void, Never>?
    /// A snippet that asks for values before it is copied (`MobileAppState+Snippets.swift`).
    var pendingFill: SnippetFillRequest?
    @ObservationIgnored var retentionPolicy: @Sendable () -> RetentionPolicy = {
        RetentionPolicy.fromDefaults(AppDefaults.store)
    }

    @ObservationIgnored var retentionSchedule = RetentionSchedule()
    @ObservationIgnored var retentionStore: @MainActor (StorageService) -> any RetentionStore = {
        StorageRetentionStore(service: $0)
    }

    @ObservationIgnored var saveChanges: @MainActor (ModelContext) throws -> Void = { try $0.saveOrRollback() }

    /// How many times the foreground sequence ran (`MobileAppState+Activation.swift`).
    @ObservationIgnored var activationCount = 0
    @ObservationIgnored var isActivated = false
    /// iOS's last answer to whether a Pesto widget is installed.
    @ObservationIgnored var widgetIsInstalled = false
    @ObservationIgnored var widgetRewrite: Task<Void, Never>?
    @ObservationIgnored var widgetWrites: Task<Void, Never>?
    @ObservationIgnored var widgetObserver: (any NSObjectProtocol)?
    /// What was last written, so a rewrite keeps the thumbnails of the pictures still in it.
    @ObservationIgnored var lastWidgetSnapshot: WidgetSnapshot?
    @ObservationIgnored let clock: @MainActor () -> Date

    static let noticeDuration: Duration = .seconds(4)
    static let undoOfferDuration: Duration = .seconds(8)

    init(
        secretReveal: SecretReveal? = nil, historyLock: MobileHistoryLock? = nil,
        clock: @escaping @MainActor () -> Date = { .now }
    ) {
        self.secretReveal = secretReveal ?? SecretReveal()
        self.historyLock = historyLock ?? MobileHistoryLock()
        self.clock = clock
        self.secretReveal.coverWasRaised = { [weak self] in self?.decodedJWT = nil }
    }

    isolated deinit {
        if let quickInsertObserver { NotificationCenter.default.removeObserver(quickInsertObserver) }
        if let widgetObserver { NotificationCenter.default.removeObserver(widgetObserver) }
    }

    static var standardOpeners: StorageBoot.Openers {
        .init(
            clips: { try ModelContainerSetup.openClips() },
            inMemory: { try ModelContainerSetup.makeInMemory() }
        )
    }

    func boot(
        openers: StorageBoot.Openers = MobileAppState.standardOpeners,
        environment: (() -> StorageEnvironment)? = nil
    ) {
        guard !hasBooted else { return }
        hasBooted = true
        let boot = StorageBoot.run(openers: openers)
        historyContainer = boot.container
        storeIsOnDisk = boot.isOnDisk
        guard let container = boot.container else { return }
        let store = HistoryStore(container: container)
        store.setVisible(!historyLock.isLocked)
        historyStore = store
        let service = StorageService(
            modelContainer: container,
            environment: environment?() ?? .live(
                rules: ClipboardRules.fromUserDefaults(),
                remoteGIFFetcher: RemoteGIFFetcher.make(isHistoryLocked: { [weak self] in
                    await MainActor.run { self?.isHistoryLockedNow() ?? true }
                })
            )
        )
        storageService = service
        if LaunchMode.current != .hostedTests { ShareFile.removeAll() }
        startQuickInsert(container: container)
        startWidget(container: container)
        launchWork = Task(priority: .utility) {
            await LaunchMigrator.run(LaunchMigration.standard(service: service))
            // A clip saved before it was judged, when Pesto was last stopped, is judged now, as the Mac does at launch.
            await service.resumePendingAnalysis()
            await self.pruneHistory(force: true)
            #if DEBUG
            await MobileSeed.runIfAsked(state: self)
            #endif
        }
    }
}

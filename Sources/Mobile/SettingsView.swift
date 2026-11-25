// SPDX-License-Identifier: MIT
import AuthenticationServices
import PestoCore
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The few settings the iOS app has. What only a Mac does (shortcuts, the login item, app exclusions) is not here.
struct SettingsView: View {
    var onClose: (() -> Void)?
    @Environment(MobileAppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pestoAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @AppStorage(Setting.appTheme) private var theme: String
    @AppStorage(Setting.appThemeDark) private var darkTheme: String
    @AppStorage(Setting.accentColorHex) private var accentColorHex: String
    @AppStorage(Setting.appearanceMode) private var appearance: String
    @AppStorage(Setting.authenticationGraceMinutes) private var graceMinutes: Int
    @AppStorage(Setting.addsCopiesOnOpen) private var addsCopiesOnOpen: Bool
    @AppStorage(Setting.defaultPasteCollectionID) private var defaultPasteCollectionID: String
    @AppStorage(Setting.showsClipsOutsideWhileLocked) private var showsClipsOutsideWhileLocked: Bool
    @AppStorage(Setting.syncEnabled) private var syncEnabled: Bool
    @AppStorage(Setting.widgetsEnabled) private var widgetsEnabled: Bool
    @AppStorage(Setting.nsfwMode) private var nsfwModeRaw: String
    @AppStorage(Setting.biometricLockEnabled) private var lockEnabled: Bool
    @AppStorage(Setting.linkPreviews) private var linkPreviews: Bool
    @AppStorage(Setting.retentionDays) private var retentionDays: Int
    @AppStorage(Setting.retentionMaxItems) private var retentionMaxItems: Int
    @AppStorage(Setting.hiddenMobileCollections) private var hiddenCollectionsStored: String
    @State private var pendingRetention: PendingRetention?
    @AppStorage(Setting.screenSharingPrivacy) private var coversWhileCaptured: Bool
    @State private var biometry = DeviceAuthenticationWords.biometry()
    @State private var clearCount = 0
    @State private var isConfirmingClear = false
    @State private var isAutoFillEnabled = false
    @State private var isKeyboardAdded = false
    @State private var exportedShare: ClipShare?
    @State private var isExportingHistory = false
    @State private var activeImport: ImportKind?

    private enum ImportKind {
        case collection
        case history
    }

    private struct PendingRetention: Identifiable {
        let id = UUID()
        let days: Int
        let maxItems: Int
        let count: Int
    }

    var body: some View {
        Form {
            appearanceSection
            Section {
                Toggle("Add copies when Pesto opens", isOn: $addsCopiesOnOpen)
                    .accessibilityIdentifier(MobileAccessibilityID.addsCopiesToggle)
                    .onChange(of: addsCopiesOnOpen) { _, on in
                        if on {
                            Task { await appState.clipboardDidBecomeActive() }
                        }
                    }
                if addsCopiesOnOpen {
                    Button("Allow Paste Without Asking\u{2026}") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                if !manualCollections.isEmpty {
                    Picker("Save pasted clips to", selection: defaultPasteBinding) {
                        Text("All Clips").tag("")
                        ForEach(manualCollections) { board in
                            Text(board.name).tag(board.id.uuidString)
                        }
                    }
                    .tint(accent)
                    .id(resolvedAccentHex)
                }
                Picker("Keep clips for", selection: retentionDaysChoice) {
                    ForEach(RetentionChoices.ageDays, id: \.self) { Text(RetentionChoices.ageLabel($0)).tag($0) }
                    if !RetentionChoices.isPresetAge(retentionDays) {
                        Text(String(localized: "Custom (\(retentionDays) days)")).tag(retentionDays)
                    }
                }
                .tint(accent)
                .id(resolvedAccentHex)
                .accessibilityIdentifier(MobileAccessibilityID.retentionAgePicker)
                Picker("Keep at most", selection: retentionMaxItemsChoice) {
                    ForEach(RetentionChoices.itemCounts, id: \.self) { Text("\($0.formatted()) clips").tag($0) }
                    if !RetentionChoices.isPresetCount(retentionMaxItems) {
                        Text(String(localized: "Custom (\(retentionMaxItems) clips)")).tag(retentionMaxItems)
                    }
                }
                .tint(accent)
                .id(resolvedAccentHex)
            } header: {
                Text("History & Capture")
            } footer: {
                if manualCollections.isEmpty {
                    Text(
                        "Pinned clips are always kept. To skip the iOS paste prompt when Pesto opens, set Paste from " +
                            "Other Apps to Allow in iOS Settings."
                    )
                } else {
                    Text(
                        "Pinned clips and clips in a collection are never removed by retention or Clear History. " +
                            "To skip the iOS paste prompt when Pesto opens, set Paste from Other Apps to Allow in " +
                            "iOS Settings."
                    )
                }
            }
            Section {
                Toggle(DeviceAuthenticationWords.lockToggleTitle(for: biometry), isOn: lockBinding)
                    .disabled(!lockEnabled && !appState.historyLock.canAuthenticate)
                    .accessibilityIdentifier(MobileAccessibilityID.historyLockToggle)
                if lockEnabled {
                    Toggle("Allow in Widgets and Keyboard while locked", isOn: $showsClipsOutsideWhileLocked)
                        .accessibilityIdentifier(MobileAccessibilityID.showsClipsOutsideToggle)
                        .onChange(of: showsClipsOutsideWhileLocked) { appState.showsClipsOutsideSettingChanged() }
                    Picker(DeviceAuthenticationWords.graceTitle(for: biometry), selection: $graceMinutes) {
                        ForEach(AuthenticationGrace.choices, id: \.self) { minutes in
                            Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes])))
                                .tag(minutes)
                        }
                    }
                    .tint(accent)
                    .id(resolvedAccentHex)
                }
                Toggle("Load link previews", isOn: $linkPreviews)
                    .accessibilityIdentifier(MobileAccessibilityID.linkPreviewsToggle)
                Picker("Explicit pictures and links", selection: $nsfwModeRaw) {
                    Text("Blur").tag(NSFWMode.blur.rawValue)
                    Text("Hide").tag(NSFWMode.hide.rawValue)
                    Text("Show").tag(NSFWMode.show.rawValue)
                }
                .tint(accent)
                .id(resolvedAccentHex)
                .onChange(of: nsfwModeRaw) { _, newValue in
                    Task {
                        if NSFWMode(rawValue: newValue)?.detectsContent == true,
                           let service = appState.storageService
                        {
                            _ = try? await service.rescanNSFWImages()
                        }
                        appState.writeQuickInsert()
                        await appState.writeWidget()
                    }
                }
                Toggle("Hide clips while the screen is recorded or shared", isOn: $coversWhileCaptured)
                    .accessibilityIdentifier(MobileAccessibilityID.captureCoverToggle)
                    .onChange(of: coversWhileCaptured) { _, on in appState.secretReveal.coversWhileCaptured = on }
                Toggle("Hide clip contents now", isOn: hiddenByHand)
                    .accessibilityIdentifier(MobileAccessibilityID.hideContentsToggle)
            } header: {
                Text("Privacy")
            } footer: {
                Text(
                    "Masked secrets and screen-capture covers stay hidden until shown. Only link previews ever " +
                        "contact a link\u{2019}s site."
                )
            }
            AppleIntelligenceSection()
            Section("Extensions & Sync") {
                NavigationLink {
                    KeyboardSettingsView()
                } label: {
                    LabeledContent(
                        "Keyboard & AutoFill",
                        value: (isAutoFillEnabled || isKeyboardAdded)
                            ? String(localized: "On")
                            : String(localized: "Set Up")
                    )
                }
                NavigationLink {
                    WidgetSettingsView()
                } label: {
                    LabeledContent(
                        "Widgets",
                        value: widgetsEnabled ? String(localized: "On") : String(localized: "Off")
                    )
                }
                NavigationLink {
                    SyncSettingsView()
                } label: {
                    LabeledContent(
                        "Sync",
                        value: syncEnabled ? String(localized: "On") : String(localized: "Off")
                    )
                }
            }
            hiddenCollectionsSection
            dataSection
            Section {
                Button("Clear History", role: .destructive) { Task { await askToClear() } }
            } footer: {
                Text(
                    manualCollections.isEmpty
                        ? "Pinned clips are kept."
                        : "Pinned clips and clips in collections are kept."
                )
            }
            Section {
                Button("Show Welcome Again") {
                    appState.requestWelcomeAgain()
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                }
                .accessibilityIdentifier(MobileAccessibilityID.showWelcomeAgain)
            } footer: {
                Text(AppVersion.displayString())
            }
        }
        .tint(accent)
        .navigationTitle("Settings")
        .onAppear {
            MobileAppState.migrateQuickInsertSettingsIfNeeded()
            Task { await refreshQuickInsertStatus() }
        }
        .task { await refreshQuickInsertStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshQuickInsertStatus() }
            }
        }
        .confirmationDialog(
            String(localized: "Clear \(clearCount) clips?"), isPresented: $isConfirmingClear, titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { Task { await appState.clearHistory() } }
        } message: {
            Text(
                manualCollections.isEmpty
                    ? "This deletes every clip that is not pinned. It can\u{2019}t be undone."
                    : "This deletes every clip that is not pinned or in a collection. It can\u{2019}t be undone."
            )
        }
        .confirmationDialog(
            String(localized: "Delete \(pendingRetention?.count ?? 0) clips?"), isPresented: isConfirmingRetention,
            titleVisibility: .visible, presenting: pendingRetention
        ) { change in
            Button("Delete", role: .destructive) { apply(change) }
        } message: { _ in
            Text(
                manualCollections.isEmpty
                    ? "Clips past the new limit are deleted now. Pinned clips stay. It can\u{2019}t be undone."
                    : "Clips past the new limit are deleted now. Pinned clips and clips in collections stay. " +
                    "It can\u{2019}t be undone."
            )
        }
        .sheet(item: $exportedShare) { share in
            ShareSheet(items: share.items, files: share.files).presentationDetents([.medium, .large])
        }
        .onDisappear {
            exportedShare?.files.forEach(ShareFile.remove)
        }
        .fileImporter(
            isPresented: isImportingFile,
            allowedContentTypes: activeImport == .history ? [.json] : CollectionFileType.importableTypes
        ) { result in
            let kind = activeImport
            activeImport = nil
            guard case let .success(url) = result else { return }
            switch kind {
            case .collection:
                _ = appState.openCollectionFile(url)
            case .history:
                Task { await appState.importHistoryJSON(from: url) }
            case nil:
                break
            }
        }
        .collectionImportConfirmation(active: canConfirmCollectionImport)
    }

    private var isImportingFile: Binding<Bool> {
        Binding(get: { activeImport != nil }, set: { if !$0 { activeImport = nil } })
    }

    private var canConfirmCollectionImport: Bool {
        exportedShare == nil && !isConfirmingClear && pendingRetention == nil && activeImport == nil
            && (appState.sync?.flow ?? .idle) == .idle && appState.sync?.pendingJoin == nil
    }

    private var manualCollections: [Pinboard] {
        collections.filter { !$0.isSmart }
    }

    private var defaultPasteBinding: Binding<String> {
        Binding(
            get: {
                guard let id = UUID(uuidString: defaultPasteCollectionID),
                      manualCollections.contains(where: { $0.id == id }) else { return "" }
                return id.uuidString
            },
            set: { defaultPasteCollectionID = $0 }
        )
    }

    private var retentionDaysChoice: Binding<Int> {
        Binding(get: { retentionDays }, set: { askToChangeRetention(days: $0, maxItems: retentionMaxItems) })
    }

    private var retentionMaxItemsChoice: Binding<Int> {
        Binding(get: { retentionMaxItems }, set: { askToChangeRetention(days: retentionDays, maxItems: $0) })
    }

    private var isConfirmingRetention: Binding<Bool> {
        Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })
    }

    private func askToChangeRetention(days: Int, maxItems: Int) {
        Task {
            let count = await appState.clipsLeaving(days: days, maxItems: maxItems)
            let change = PendingRetention(days: days, maxItems: maxItems, count: count)
            if count > 0 { pendingRetention = change } else { apply(change) }
        }
    }

    private func apply(_ change: PendingRetention) {
        retentionDays = change.days
        retentionMaxItems = change.maxItems
        pendingRetention = nil
        Task { await appState.pruneHistory() }
    }

    private func askToClear() async {
        clearCount = await appState.nonPinnedCount()
        if clearCount > 0 {
            isConfirmingClear = true
        } else {
            appState.tell(String(localized: "There is nothing to clear."))
        }
    }

    /// Turning the lock on needs a device that can authenticate; turning it off asks again, always (ADR 0003).
    private var lockBinding: Binding<Bool> {
        Binding(get: { lockEnabled }, set: { wantsOn in
            if wantsOn {
                guard HistoryLockPolicy.canSwitchOn(using: appState.historyLock.authenticator) else { return }
                lockEnabled = true
                appState.historyLockSettingChanged()
                return
            }
            Task {
                guard await HistoryLockPolicy.permitsTurningLockOff(
                    using: appState.historyLock.authenticator, reason: String(localized: "Turn off the history lock"),
                    grace: appState.historyLock.grace
                ) else { return }
                lockEnabled = false
                appState.historyLockSettingChanged()
            }
        })
    }

    private var resolvedAccentHex: String {
        MobileTheme.resolve(
            accent: accentColorHex, theme: theme, darkTheme: darkTheme, isDark: colorScheme == .dark
        ).accentHex
    }

    private var activeThemeBinding: Binding<String> {
        Binding(
            get: { AppTheme.resolve(light: theme, dark: darkTheme, isDark: colorScheme == .dark).rawValue },
            set: { newValue in
                if colorScheme == .dark {
                    darkTheme = newValue
                } else {
                    theme = newValue
                }
            }
        )
    }

    private var hiddenByHand: Binding<Bool> {
        Binding(
            get: { appState.secretReveal.isHiddenByHand },
            set: { appState.secretReveal.isHiddenByHand = $0 }
        )
    }

    private func refreshQuickInsertStatus() async {
        let state = await ASCredentialIdentityStore.shared.state()
        isAutoFillEnabled = state.isEnabled
        isKeyboardAdded = UITextInputMode.activeInputModes.contains { mode in
            (mode.value(forKey: "identifier") as? String)?.contains("net.copypesto.pesto") == true
        }
    }
}

private extension SettingsView {
    @ViewBuilder
    var hiddenCollectionsSection: some View {
        let hiddenIDs = HiddenCollections.ids(from: hiddenCollectionsStored)
        let hiddenBoards = collections.filter { hiddenIDs.contains($0.id) }
        if !hiddenBoards.isEmpty {
            Section("Hidden Collections") {
                ForEach(hiddenBoards) { board in
                    Button {
                        hiddenCollectionsStored = HiddenCollections.toggle(board.id, in: hiddenCollectionsStored)
                        appState.writeQuickInsert()
                    } label: {
                        LabeledContent(board.name, value: String(localized: "Show"))
                    }
                }
                Button("Show All Collections") {
                    hiddenCollectionsStored = ""
                    appState.writeQuickInsert()
                }
            }
        }
    }

    var dataSection: some View {
        Section {
            NavigationLink(value: LibraryModel.SettingsDestination.insights) {
                Label("Insights", systemImage: "chart.bar.xaxis")
            }
            .accessibilityIdentifier(MobileAccessibilityID.insightsButton)
            Button("Import Collection (.pesto)\u{2026}") {
                activeImport = .collection
            }
            .accessibilityIdentifier(MobileAccessibilityID.importCollectionButton)
            Button("Export History (JSON)\u{2026}") {
                guard !isExportingHistory else { return }
                isExportingHistory = true
                Task {
                    defer { isExportingHistory = false }
                    if let url = await appState.exportHistoryJSON() {
                        exportedShare = ClipShare(file: url)
                    }
                }
            }
            .disabled(isExportingHistory)
            .accessibilityIdentifier(MobileAccessibilityID.exportHistoryButton)
            Button("Import History (JSON)\u{2026}") {
                activeImport = .history
            }
            .accessibilityIdentifier(MobileAccessibilityID.importHistoryButton)
        } header: {
            Text("Data")
        } footer: {
            Text("Collections share as .pesto files with their clips. History exports save text clips as JSON.")
        }
    }
}

struct SettingsSheet: View {
    var onClose: (() -> Void)?
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pestoSurface) private var ground
    @State private var path: [LibraryModel.SettingsDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            SettingsView(onClose: onClose)
                .scrollContentBackground(.hidden)
                .background(ground.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
                .navigationDestination(for: LibraryModel.SettingsDestination.self) { destination in
                    switch destination {
                    case .keyboard: KeyboardSettingsView()
                    case .sync: SyncSettingsView()
                    case .insights: MobileInsightsView()
                    }
                }
        }
        .overlay(alignment: .bottom) { LibraryBanners(messagesOnly: true) }
        .modifier(MobileAccent())
        .onAppear {
            if let destination = library.settingsDestination {
                path = [destination]
            }
        }
        .onChange(of: library.settingsDestination) { _, destination in
            if let destination {
                path = [destination]
            } else {
                path = []
            }
        }
    }
}

extension SettingsView {
    var appearanceSection: some View {
        Section {
            Picker("Theme", selection: activeThemeBinding) {
                ForEach(AppTheme.allCases, id: \.rawValue) { choice in
                    Text(choice.displayName).tag(choice.rawValue)
                }
            }
            .tint(accent)
            .id(resolvedAccentHex)
            .onChange(of: theme) {
                appState.writeQuickInsert()
                Task { await appState.writeWidget() }
            }
            .onChange(of: darkTheme) {
                appState.writeQuickInsert()
                Task { await appState.writeWidget() }
            }
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .tint(accent)
            .id(resolvedAccentHex)
            MobileAccentPicker(selection: $accentColorHex, theme: theme, darkTheme: darkTheme)
                .onChange(of: accentColorHex) {
                    appState.writeQuickInsert()
                    Task { await appState.writeWidget() }
                }
            MobileAppIconToggle()
        } header: {
            Text("Appearance")
        } footer: {
            Text("Your Home Screen icon follows the theme when you leave Settings. iOS asks to confirm.")
        }
    }
}

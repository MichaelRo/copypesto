// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The few settings the iOS app has. What only a Mac does (shortcuts, the login item, app exclusions) is not here.
struct SettingsView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @AppStorage(Setting.appTheme) private var theme: String
    @AppStorage(Setting.appearanceMode) private var appearance: String
    @AppStorage(Setting.authenticationGraceMinutes) private var graceMinutes: Int
    @AppStorage(Setting.addsCopiesOnOpen) private var addsCopiesOnOpen: Bool
    @AppStorage(Setting.showsClipsOutsideWhileLocked) private var showsClipsOutsideWhileLocked: Bool
    @AppStorage(Setting.syncEnabled) private var syncEnabled: Bool
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

    private struct PendingRetention: Identifiable {
        let id = UUID()
        let days: Int
        let maxItems: Int
        let count: Int
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { choice in
                        Text(choice.displayName).tag(choice.rawValue)
                    }
                }
                .onChange(of: theme) { appState.writeQuickInsert() }
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }
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
                        _ = AppPasteboard.general.hasStrings
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Picker("Keep clips for", selection: retentionDaysChoice) {
                    ForEach(RetentionChoices.ageDays, id: \.self) { Text(RetentionChoices.ageLabel($0)).tag($0) }
                    if !RetentionChoices.isPresetAge(retentionDays) {
                        Text(String(localized: "Custom (\(retentionDays) days)")).tag(retentionDays)
                    }
                }
                .accessibilityIdentifier(MobileAccessibilityID.retentionAgePicker)
                Picker("Keep at most", selection: retentionMaxItemsChoice) {
                    ForEach(RetentionChoices.itemCounts, id: \.self) { Text("\($0.formatted()) clips").tag($0) }
                    if !RetentionChoices.isPresetCount(retentionMaxItems) {
                        Text(String(localized: "Custom (\(retentionMaxItems) clips)")).tag(retentionMaxItems)
                    }
                }
            } header: {
                Text("History & Capture")
            } footer: {
                Text(
                    "Pinned clips are always kept. To skip the iOS paste prompt when Pesto opens, set Paste from " +
                        "Other Apps to Allow in iOS Settings."
                )
            }
            Section {
                Toggle(DeviceAuthenticationWords.lockToggleTitle(for: biometry), isOn: lockBinding)
                    .disabled(!lockEnabled && !appState.historyLock.canAuthenticate)
                    .accessibilityIdentifier(MobileAccessibilityID.historyLockToggle)
                if lockEnabled {
                    Toggle("Allow in Widgets and Keyboard while locked", isOn: $showsClipsOutsideWhileLocked)
                        .accessibilityIdentifier(MobileAccessibilityID.showsClipsOutsideToggle)
                        .onChange(of: showsClipsOutsideWhileLocked) { appState.showsClipsOutsideSettingChanged() }
                }
                Picker(DeviceAuthenticationWords.graceTitle(for: biometry), selection: $graceMinutes) {
                    ForEach(AuthenticationGrace.choices, id: \.self) { minutes in
                        Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes])))
                            .tag(minutes)
                    }
                }
                Toggle("Load link previews", isOn: $linkPreviews)
                    .accessibilityIdentifier(MobileAccessibilityID.linkPreviewsToggle)
                Picker("Explicit pictures and links", selection: $nsfwModeRaw) {
                    Text("Blur").tag(NSFWMode.blur.rawValue)
                    Text("Hide").tag(NSFWMode.hide.rawValue)
                    Text("Show").tag(NSFWMode.show.rawValue)
                }
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
            Section {
                NavigationLink("Keyboard & AutoFill") { KeyboardSettingsView() }
                NavigationLink {
                    SyncSettingsView()
                } label: {
                    LabeledContent(
                        "Sync",
                        value: syncEnabled ? String(localized: "On") : String(localized: "Off")
                    )
                }
            }
            let hiddenIDs = HiddenCollections.ids(from: hiddenCollectionsStored)
            let hiddenBoards = collections.filter { hiddenIDs.contains($0.id) }
            if !hiddenBoards.isEmpty {
                Section("Hidden Collections") {
                    ForEach(hiddenBoards) { board in
                        Button {
                            hiddenCollectionsStored = HiddenCollections.toggle(board.id, in: hiddenCollectionsStored)
                        } label: {
                            LabeledContent(board.name, value: String(localized: "Show"))
                        }
                    }
                    Button("Show All Collections") {
                        hiddenCollectionsStored = ""
                    }
                }
            }
            Section {
                Button("Clear History", role: .destructive) { Task { await askToClear() } }
            } footer: {
                Text("Pinned clips are kept.")
            }
            Section {
                HStack {
                    Button("Show Welcome Again") {
                        appState.requestWelcomeAgain()
                        dismiss()
                    }
                    .accessibilityIdentifier(MobileAccessibilityID.showWelcomeAgain)
                    Spacer()
                    Text(AppVersion.displayString())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            MobileAppState.migrateQuickInsertSettingsIfNeeded()
        }
        .confirmationDialog(
            String(localized: "Clear \(clearCount) clips?"), isPresented: $isConfirmingClear, titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { Task { await appState.clearHistory() } }
        } message: {
            Text("This deletes every clip that is not pinned. It can\u{2019}t be undone.")
        }
        .confirmationDialog(
            String(localized: "Delete \(pendingRetention?.count ?? 0) clips?"), isPresented: isConfirmingRetention,
            titleVisibility: .visible, presenting: pendingRetention
        ) { change in
            Button("Delete", role: .destructive) { apply(change) }
        } message: { _ in
            Text("Clips past the new limit are deleted now. Pinned clips stay. It can\u{2019}t be undone.")
        }
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

    private var hiddenByHand: Binding<Bool> {
        Binding(
            get: { appState.secretReveal.isHiddenByHand },
            set: { appState.secretReveal.isHiddenByHand = $0 }
        )
    }
}

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pestoSurface) private var ground

    var body: some View {
        NavigationStack {
            SettingsView()
                .scrollContentBackground(.hidden)
                .background(ground.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

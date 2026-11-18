// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The few settings the iOS app has. What only a Mac does (shortcuts, the login item, app exclusions) is not here.
struct SettingsView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Setting.appTheme) private var theme: String
    @AppStorage(Setting.appearanceMode) private var appearance: String
    @AppStorage(Setting.authenticationGraceMinutes) private var graceMinutes: Int
    @AppStorage(Setting.addsCopiesOnOpen) private var addsCopiesOnOpen: Bool
    @AppStorage(Setting.quickInsertEnabled) private var quickInsertEnabled: Bool
    @AppStorage(Setting.biometricLockEnabled) private var lockEnabled: Bool
    @AppStorage(Setting.showsClipsOutsideWhileLocked) private var showsClipsOutside: Bool
    @AppStorage(Setting.linkPreviews) private var linkPreviews: Bool
    @AppStorage(Setting.retentionDays) private var retentionDays: Int
    @AppStorage(Setting.retentionMaxItems) private var retentionMaxItems: Int
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
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }
            Section {
                Toggle("Add copies when Pesto opens", isOn: $addsCopiesOnOpen)
                    .accessibilityIdentifier(MobileAccessibilityID.addsCopiesToggle)
            } header: {
                Text("Clipboard")
            } footer: {
                Text(
                    "Pesto adds what you copied in another app each time it opens, and iOS asks for permission to " +
                        "paste. Off, Pesto offers it with a Paste button and never reads the clipboard on its own."
                )
            }
            Section {
                Toggle("Insert from Pesto in other apps", isOn: $quickInsertEnabled)
                    .accessibilityIdentifier(MobileAccessibilityID.quickInsertToggle)
                    .onChange(of: quickInsertEnabled) { appState.quickInsertSettingChanged() }
            } header: {
                Text("AutoFill")
            } footer: {
                Text(
                    "Pesto keeps a small set of your pinned and recent text clips ready, sealed, so AutoFill can " +
                        "insert one in any text field. Clips with secrets are never in it. To use it, turn on Pesto " +
                        "in Settings > General > AutoFill & Passwords."
                )
            }
            Section {
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
                Text("History")
            } footer: {
                Text("Pinned clips are always kept.")
            }
            Section {
                Toggle(DeviceAuthenticationWords.lockToggleTitle(for: biometry), isOn: lockBinding)
                    .disabled(!lockEnabled && !appState.historyLock.canAuthenticate)
                    .accessibilityIdentifier(MobileAccessibilityID.historyLockToggle)
                Toggle("Show clips in widgets and AutoFill", isOn: $showsClipsOutside)
                    .disabled(!lockEnabled)
                    .onChange(of: showsClipsOutside) { appState.showsClipsOutsideSettingChanged() }
                    .accessibilityIdentifier(MobileAccessibilityID.showsClipsOutsideToggle)
                Picker(DeviceAuthenticationWords.graceTitle(for: biometry), selection: $graceMinutes) {
                    ForEach(AuthenticationGrace.choices, id: \.self) { minutes in
                        Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes])))
                            .tag(minutes)
                    }
                }
                Toggle("Load link previews", isOn: $linkPreviews)
                    .accessibilityIdentifier(MobileAccessibilityID.linkPreviewsToggle)
            } header: {
                Text("Privacy")
            } footer: {
                Text(
                    "With the lock on, Pesto asks when it opens and after it has been away this long. The widget " +
                        "says Locked and AutoFill holds nothing, unless you show clips there, which anyone holding " +
                        "this device can then read. Hidden clips stay masked until you show them. Copying one " +
                        "never shows it. Link previews contact the page a link points to, once, to show its title " +
                        "and picture; " +
                        "nothing else leaves this device."
                )
            }
            Section {
                Toggle("Hide clips while the screen is recorded or shared", isOn: $coversWhileCaptured)
                    .accessibilityIdentifier(MobileAccessibilityID.captureCoverToggle)
                    .onChange(of: coversWhileCaptured) { _, on in appState.secretReveal.coversWhileCaptured = on }
                Toggle("Hide clip contents now", isOn: hiddenByHand)
                    .accessibilityIdentifier(MobileAccessibilityID.hideContentsToggle)
            } footer: {
                Text(
                    "While iOS records, mirrors or AirPlays the screen, cards show only their kind until you show " +
                        "one. Hiding by hand lasts until you show the contents again or Pesto quits."
                )
            }
            AppleIntelligenceSection()
            Section {
                NavigationLink("Sync") { SyncSettingsView() }
            }
            Section {
                Button("Clear History", role: .destructive) { Task { await askToClear() } }
            } footer: {
                Text("Pinned clips are kept.")
            }
            Section {
                Button("Show Welcome Again") {
                    appState.requestWelcomeAgain()
                    dismiss()
                }
                .accessibilityIdentifier(MobileAccessibilityID.showWelcomeAgain)
                LabeledContent("Pesto", value: AppVersion.displayString())
            }
        }
        .navigationTitle("Settings")
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

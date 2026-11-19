// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

struct GeneralSettings: View {
    enum Part {
        case startup, shelf, copyPaste, floatingWindow, retention
    }

    let part: Part
    @AppStorage(Setting.retentionDays) private var retentionDays: Int
    @AppStorage(Setting.retentionMaxItems) private var retentionMaxItems: Int
    @AppStorage(Setting.clearOnScreenLock) private var clearOnScreenLock: Bool
    @AppStorage(Setting.clearOnQuit) private var clearOnQuit: Bool
    @AppStorage(Setting.pinnedWindowAutoPaste) private var pinnedWindowAutoPaste: Bool
    @AppStorage(Setting.soundEffects) private var soundEffects: Bool
    @AppStorage(Setting.pictureSaveFolder) private var pictureSaveFolder: String
    @AppStorage(Setting.opensQuickMenuAtCursor) private var opensQuickMenuAtCursor: Bool
    @AppStorage(Setting.showMenuBarIcon) private var showMenuBarIcon: Bool
    @AppStorage(Setting.shelfSuggestionsEnabled) private var shelfSuggestionsEnabled: Bool
    @AppStorage(Setting.doubleCopyAppend) private var doubleCopyAppend: Bool
    @State private var isAXTrusted = AccessibilityAccess.isTrusted
    @State private var iconIsLeftOut = false
    @Environment(AppState.self) private var appState: AppState
    @State private var checksForUpdates = true
    @State private var installsUpdates = false

    var body: some View {
        switch part {
        case .startup: startupSection
        case .shelf: shelfSection
        case .copyPaste: copyPasteSection
        case .floatingWindow: floatingWindowSection
        case .retention: retentionSection
        }
    }

    private var openShelfShortcut: String {
        HotkeyDescription.overlay(
            storedKeyCode: AppDefaults.store.value(for: Setting.overlayHotkeyKeyCode),
            storedModifiers: AppDefaults.store.value(for: Setting.overlayHotkeyModifiers)
        )
    }

    private var hiddenIconHint: String {
        iconHint(lead: "Hidden — ")
    }

    private var crowdedBarHint: String {
        iconHint(lead: "Menu bar is full — ")
    }

    private func iconHint(lead: String) -> String {
        let reopen = "open Pesto from Applications for Settings."
        guard !openShelfShortcut.isEmpty else { return lead + reopen }
        return lead + "press \(openShelfShortcut) for the shelf, or \(reopen)"
    }

    /// A status item takes a moment to be placed, and the person may free room in the bar, so this looks again when
    /// Settings opens and when the toggle changes.
    private func checkWhetherTheIconIsSeen() async {
        guard showMenuBarIcon, let isOnScreen = appState.menuBarIconIsOnScreen else { return iconIsLeftOut = false }
        try? await Task.sleep(for: .milliseconds(600))
        iconIsLeftOut = showMenuBarIcon && !isOnScreen()
    }

    private var startupSection: some View {
        Section {
            LoginItemToggle(title: "Launch Pesto at login")
            Toggle(isOn: $showMenuBarIcon) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Pesto in the menu bar")
                    if !showMenuBarIcon {
                        Text(hiddenIconHint).pestoCaption().lineLimit(1)
                    } else if iconIsLeftOut {
                        Text(crowdedBarHint).pestoCaption().lineLimit(1)
                            .accessibilityIdentifier(AccessibilityID.settingsChoice("menuBarIcon", "crowdedHint"))
                    }
                }
            }
            .task(id: showMenuBarIcon) { await checkWhetherTheIconIsSeen() }
            .accessibilityIdentifier(AccessibilityID.settingsChoice("menuBarIcon", "toggle"))
            .settingsRow("Menu bar icon")
            if let updates = appState.automaticUpdateChecks {
                Toggle("Check for updates automatically", isOn: $checksForUpdates)
                    .onAppear { checksForUpdates = updates.get() }
                    .onChange(of: checksForUpdates) { _, on in updates.set(on) }
                    .settingsRow("Check for updates automatically")
                if let installs = appState.automaticUpdateInstalls {
                    Toggle("Install updates automatically", isOn: $installsUpdates)
                        .onAppear { installsUpdates = installs.get() }
                        .onChange(of: installsUpdates) { _, on in installs.set(on) }
                        .accessibilityIdentifier(AccessibilityID.settingsChoice("installUpdates", "toggle"))
                        .settingsRow("Install updates automatically")
                }
            }
        } footer: {
            if appState.automaticUpdateChecks != nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(UpdateCheckCaption.text(lastCheck: appState.lastUpdateCheck)).pestoCaption()
                        InfoPopoverButton(
                            title: "Automatic updates",
                            message: "Pesto asks copypesto.net whether a new version exists. The request carries " +
                                "Pesto\u{2019}s version and your IP address, and nothing from your clips. When " +
                                "automatic install is on, a new version installs when Pesto quits; when off, " +
                                "Pesto asks first."
                        )
                        Spacer()
                        Button("Check Now") { appState.checkForUpdates?() }
                            .controlSize(.small)
                            .disabled(appState.checkForUpdates == nil)
                    }
                    if let staged = appState.stagedUpdate {
                        HStack(spacing: 8) {
                            Text("Pesto \(staged.version) is ready. It installs when Pesto quits.").pestoCaption()
                            Spacer()
                            if let notes = staged.whatsNew {
                                Link("What\u{2019}s New", destination: notes).buttonStyle(.pestoLink)
                            }
                            Button("Restart Now") { staged.install() }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var shelfSection: some View {
        Section {
            Toggle("Open a small menu at the cursor", isOn: $opensQuickMenuAtCursor)
                .settingsRow("Open a small menu at the cursor")
            LabeledContent("Show suggestions on the shelf") {
                HStack(spacing: 10) {
                    Button("Reset Suggestions") {
                        appState.resetShelfSuggestions()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier(AccessibilityID.resetSuggestionsButton)
                    Toggle("Show suggestions on the shelf", isOn: $shelfSuggestionsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier(AccessibilityID.shelfSuggestionsSettingsToggle)
                }
            }
            .settingsRow("Show suggestions on the shelf")
        } header: {
            Text("Shelf")
        } footer: {
            HStack(spacing: 6) {
                Text(
                    opensQuickMenuAtCursor
                        ? "In text fields, the shortcut opens a menu at the cursor; suggestions use local paste counts."
                        : "The shortcut opens the full keyboard shelf; suggestions use local paste counts."
                )
                .pestoCaption()
                InfoPopoverButton(
                    title: "Shelf options",
                    message: "In a text field, at-cursor mode shows your latest clips near the caret for the mouse. " +
                        "Suggestions propose a shortcut or snippet for clips you paste often, or removing unused " +
                        "shortcuts, using paste counts kept on this Mac."
                )
            }
        }
    }

    private var copyPasteSection: some View {
        Section {
            Toggle("Play sounds on copy and paste", isOn: $soundEffects)
                .settingsRow("Play sounds on copy and paste")
            LabeledContent("Save pictures to") {
                HStack(spacing: 8) {
                    Text(pictureSaveFolder.isEmpty ? "Downloads" : URL(fileURLWithPath: pictureSaveFolder)
                        .lastPathComponent)
                        .pestoQuiet()
                    Button("Choose\u{2026}") { choosePictureFolder() }
                        .controlSize(.small)
                    if !pictureSaveFolder.isEmpty {
                        Button("Use Downloads") { pictureSaveFolder = "" }
                            .controlSize(.small)
                    }
                }
            }
            .help("\u{2318}S on a picture saves it here without asking; a name already there gets a number.")
            .settingsRow("Save pictures to")
            Toggle("Double-press ⌘C to append to the last clip", isOn: $doubleCopyAppend)
                .disabled(!isAXTrusted && !doubleCopyAppend)
                .accessibilityIdentifier(AccessibilityID.doubleCopyToggle)
                .settingsRow("Double-press ⌘C to append")
        } header: {
            Text("Copy and paste")
        } footer: {
            HStack(spacing: 6) {
                Text(
                    isAXTrusted
                        ? "Double-press \u{2318}C watches for two \u{2318}C presses within half a second."
                        : "Double-press \u{2318}C needs Accessibility permission (see Permissions below)."
                )
                .pestoCaption()
                InfoPopoverButton(
                    title: "Copy and paste options",
                    message: "\u{2318}S on a picture saves it to your chosen folder without asking. Double-press " +
                        "\u{2318}C is off by default: it watches every \u{2318}C keystroke system-wide and records " +
                        "only whether \u{2318}C was pressed twice within half a second."
                )
            }
        }
        .onAppear { isAXTrusted = AccessibilityAccess.isTrusted }
    }

    private var floatingWindowSection: some View {
        Section {
            Toggle("Paste from the floating window", isOn: $pinnedWindowAutoPaste)
                .settingsRow("Paste from the floating window")
        } header: {
            Text("Floating window")
        } footer: {
            Text(
                pinnedWindowAutoPaste
                    ? "Clicking a clip or pressing Return in the floating window pastes into the active app."
                    : "Clicking a clip or pressing Return in the floating window copies without pasting."
            )
            .pestoCaption()
        }
    }

    private var retentionSection: some View {
        Section {
            HStack(spacing: 16) {
                Picker("Keep clips for", selection: $retentionDays) {
                    ForEach(RetentionChoices.ageDays, id: \.self) { Text(Self.ageLabel($0)).tag($0) }
                    if !RetentionChoices.isPresetAge(retentionDays) {
                        Text(String(localized: "Custom (\(retentionDays) days)")).tag(retentionDays)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.settingsChoice("retention", "age"))
                .settingsRow("Keep clips for a number of days")

                Picker("Keep at most", selection: $retentionMaxItems) {
                    ForEach(RetentionChoices.itemCounts, id: \.self) { Text("\($0.formatted()) clips").tag($0) }
                    if !RetentionChoices.isPresetCount(retentionMaxItems) {
                        Text(String(localized: "Custom (\(retentionMaxItems) clips)")).tag(retentionMaxItems)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.settingsChoice("retention", "count"))
                .settingsRow("Keep up to a number of clips")
            }
            HStack(spacing: 20) {
                Toggle("Clear history when the screen locks", isOn: $clearOnScreenLock)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsRow("Clear history when the screen locks")
                Toggle("Clear history on quit", isOn: $clearOnQuit)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsRow("Clear history on quit")
            }
        } header: {
            Text("History")
        } footer: {
            Text(RetentionCaption.text(for: .chosen(days: retentionDays, maxItems: retentionMaxItems)))
                .pestoCaption()
        }
    }

    static func ageLabel(_ days: Int) -> String {
        RetentionChoices.ageLabel(days)
    }

    private func choosePictureFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK, let url = panel.url { pictureSaveFolder = url.path }
    }
}

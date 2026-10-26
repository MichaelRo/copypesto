// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

struct GeneralSettings: View {
    enum Part {
        case startup, copyPaste, retention
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
    @Environment(AppState.self) private var appState: AppState
    @State private var checksForUpdates = true

    var body: some View {
        switch part {
        case .startup: startupSection
        case .copyPaste: copyPasteSection
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
        let reopen = "open Pesto again from Applications to see Settings."
        guard !openShelfShortcut.isEmpty else { return "With the icon hidden, \(reopen)" }
        return "With the icon hidden, press \(openShelfShortcut) to open the shelf and choose Settings there, " +
            "or \(reopen)"
    }

    private var startupSection: some View {
        Section {
            LoginItemToggle(title: "Launch Pesto at login")
            Toggle(isOn: $showMenuBarIcon) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Pesto in the menu bar")
                    if !showMenuBarIcon {
                        Text(hiddenIconHint).pestoCaption()
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.settingsChoice("menuBarIcon", "toggle"))
            .settingsRow("Menu bar icon")
            if let updates = appState.automaticUpdateChecks {
                Toggle(isOn: $checksForUpdates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for updates automatically")
                        Text(
                            "Pesto asks copypesto.net whether a new version exists. The request carries Pesto's " +
                                "version and your IP address, and nothing from your clips."
                        )
                        .pestoCaption()
                    }
                }
                .onAppear { checksForUpdates = updates.get() }
                .onChange(of: checksForUpdates) { _, on in updates.set(on) }
                .settingsRow("Check for updates automatically")
            }
        }
    }

    private var copyPasteSection: some View {
        Section {
            Toggle("Play sounds on copy and paste", isOn: $soundEffects)
                .settingsRow("Play sounds on copy and paste")
            Toggle(isOn: $pinnedWindowAutoPaste) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paste from the floating window")
                    Text(
                        pinnedWindowAutoPaste
                            ? "Clicking a clip or pressing Return in the floating window pastes it into the active app."
                            : "Clicking a clip or pressing Return in the floating window copies it without pasting."
                    )
                    .pestoCaption()
                }
            }
            .settingsRow("Paste from the floating window")
            LabeledContent {
                HStack {
                    Text(pictureSaveFolder.isEmpty ? "Downloads" : URL(fileURLWithPath: pictureSaveFolder)
                        .lastPathComponent)
                        .pestoQuiet()
                    Button("Choose\u{2026}") { choosePictureFolder() }
                    if !pictureSaveFolder.isEmpty {
                        Button("Use Downloads") { pictureSaveFolder = "" }
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save pictures to")
                    Text("\u{2318}S on a picture saves it here without asking; a name already there gets a number.")
                        .pestoCaption()
                }
            }
            .settingsRow("Save pictures to")
            Toggle(isOn: $opensQuickMenuAtCursor) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open a small menu at the cursor")
                    Text(
                        opensQuickMenuAtCursor
                            ? "In a text field the shortcut shows your latest clips by the cursor, for the mouse."
                            : "The shortcut always opens the full shelf, which works fully from the keyboard."
                    )
                    .pestoCaption()
                }
            }
            .settingsRow("Open a small menu at the cursor")
            Toggle(isOn: $shelfSuggestionsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show suggestions on the shelf")
                    Text(
                        "Suggests a shortcut or a snippet for a clip you paste often, and suggests removing "
                            + "a shortcut you stopped using. It uses paste counts kept on this Mac."
                    )
                    .pestoCaption()
                }
            }
            .accessibilityIdentifier(AccessibilityID.shelfSuggestionsSettingsToggle)
            .settingsRow("Show suggestions on the shelf")
            HStack {
                Text("Reset suggestions")
                Spacer()
                Button("Reset Suggestions") {
                    appState.resetShelfSuggestions()
                }
                .accessibilityIdentifier(AccessibilityID.resetSuggestionsButton)
            }
        } header: {
            Text("Copy and paste")
        }
    }

    private var retentionSection: some View {
        Section {
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
            Toggle("Clear history when the screen locks", isOn: $clearOnScreenLock)
                .settingsRow("Clear history when the screen locks")
            Toggle("Clear history on quit", isOn: $clearOnQuit)
                .settingsRow("Clear history on quit")
        } header: {
            Text("History")
        } footer: {
            Text(RetentionCaption.text(for: .chosen(days: retentionDays, maxItems: retentionMaxItems)))
                .pestoCaption()
        }
    }

    private static func ageLabel(_ days: Int) -> String {
        switch days {
        case RetentionChoices.foreverDays: "Forever"
        case 7: "1 week"
        case 30: "1 month"
        case 90: "3 months"
        case 180: "6 months"
        case 365: "1 year"
        default: String(localized: "\(days) days")
        }
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

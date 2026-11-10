// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct OnboardingMoreOptions: View {
    var appState: AppState
    @AppStorage(Setting.showMenuBarIcon) private var showsMenuBarIcon: Bool
    @AppStorage(Setting.keepsRemoteCopies) private var keepsRemoteCopies: Bool
    @AppStorage(Setting.linkPreviews) private var linkPreviews: Bool
    @AppStorage(Setting.retentionDays) private var retentionDays: Int
    @State private var checksForUpdates: Bool

    init(appState: AppState) {
        self.appState = appState
        _checksForUpdates = State(initialValue: appState.automaticUpdateChecks?.get() ?? true)
    }

    var body: some View {
        Toggle(isOn: $showsMenuBarIcon) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Show Pesto in the menu bar")
                Text("You can always open the shelf with the shortcut.").pestoCaption()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(AccessibilityID.onboardingMenuBarToggle)
        Toggle(isOn: $keepsRemoteCopies) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Keep copies from other devices")
                Text("Clips you copy on an iPhone or iPad arrive through Universal Clipboard.")
                    .pestoCaption()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(AccessibilityID.onboardingDevicesToggle)
        Toggle(isOn: $linkPreviews) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Load link previews")
                Text(
                    "Asks the linked site for its title and picture."
                )
                .pestoCaption()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(AccessibilityID.onboardingLinkPreviewsToggle)
        Picker("Keep clips for", selection: $retentionDays) {
            ForEach(RetentionChoices.ageDays, id: \.self) { Text(GeneralSettings.ageLabel($0)).tag($0) }
        }
        .accessibilityIdentifier(AccessibilityID.onboardingRetentionPicker)
        if let updates = appState.automaticUpdateChecks {
            Toggle(isOn: $checksForUpdates) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Check for updates automatically")
                    Text(
                        "Asks copypesto.net for new versions; sends no clips."
                    )
                    .pestoCaption()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: checksForUpdates) { _, on in updates.set(on) }
            .accessibilityIdentifier(AccessibilityID.onboardingUpdatesToggle)
        }
    }
}

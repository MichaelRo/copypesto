// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct WidgetSettingsView: View {
    @Environment(MobileAppState.self) private var appState
    @AppStorage(Setting.widgetsEnabled) private var widgetsEnabled: Bool
    @AppStorage(Setting.biometricLockEnabled) private var lockEnabled: Bool
    @AppStorage(Setting.showsClipsOutsideWhileLocked) private var showsClipsOutside: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Recent Clips Widgets", isOn: $widgetsEnabled)
                    .accessibilityIdentifier(MobileAccessibilityID.widgetsToggle)
                    .onChange(of: widgetsEnabled) { _, on in
                        Task {
                            if on {
                                await appState.refreshWidgetPresence()
                            } else {
                                appState.removeWidget()
                            }
                        }
                    }
                LabeledContent("Status") {
                    Text(statusLabel)
                        .foregroundStyle(statusColor)
                }
                if lockEnabled {
                    Toggle("Show clips in widgets while locked", isOn: $showsClipsOutside)
                        .onChange(of: showsClipsOutside) { appState.showsClipsOutsideSettingChanged() }
                        .accessibilityIdentifier(MobileAccessibilityID.showsClipsOutsideToggle)
                }
            } footer: {
                Text(
                    "Secrets and explicit clips never appear in widgets. Long-press a widget on your Home Screen and " +
                        "tap Edit Widget to pick a collection or choose what tapping a clip does."
                )
            }
        }
        .navigationTitle("Widgets")
    }

    private var statusLabel: LocalizedStringKey {
        if !widgetsEnabled {
            "Off"
        } else if appState.historyLock.holdsOutsideSurfaces {
            "Locked"
        } else {
            "Active"
        }
    }

    private var statusColor: Color {
        if !widgetsEnabled {
            .secondary
        } else if appState.historyLock.holdsOutsideSurfaces {
            .orange
        } else {
            .green
        }
    }
}

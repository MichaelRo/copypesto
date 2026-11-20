// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct GeneralPane: View {
    @Environment(AppState.self) private var appState: AppState

    var body: some View {
        Form {
            GeneralSettings(part: .startup)
            GeneralSettings(part: .shelf)
            GeneralSettings(part: .copyPaste)
            GeneralSettings(part: .floatingWindow)
            GeneralSettings(part: .widgets)
            AppleIntelligenceSettings()
            CaptureSettings(part: .accessibility)
        }
        .formStyle(.grouped)
        .settingsRowScrolling()
        .settingsPaneTop {
            SettingsPaneHeader(
                symbol: "gearshape", title: "General", subtitle: Text("Starts quietly and stays out of the way.")
            ) {
                Text(AppVersion.displayString())
                    .font(.callout)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .textSelection(.enabled)
                if let openAbout = appState.openAbout {
                    Button("About Pesto", action: openAbout).buttonStyle(.bordered)
                }
            }
        }
    }
}

struct ShortcutsPane: View {
    var body: some View {
        Form {
            ShortcutsSettings()
        }
        .formStyle(.grouped)
        .settingsRowScrolling()
        .settingsPaneTop {
            SettingsPaneHeader(
                symbol: "keyboard", title: "Shortcuts",
                subtitle: Text("Keys that work in every app, and the keys that work on the shelf.")
            )
        }
    }
}

struct PrivacyPane: View {
    var body: some View {
        Form {
            PrivacySettings()
            CaptureSettings(part: .lock)
            ExclusionSettings()
            CaptureSettings(part: .sensitiveContent)
            OtherDevicesSettings()
        }
        .formStyle(.grouped)
        .settingsRowScrolling()
        .settingsPaneTop {
            SettingsPaneHeader(
                symbol: "hand.raised", title: "Privacy",
                subtitle: Text("Encrypted on this Mac. Pesto sends no clips anywhere.")
            )
        }
    }
}

struct DataPane: View {
    let hasStorage: Bool
    @Environment(AppState.self) private var appState: AppState
    @State private var showingInsights = false

    var body: some View {
        Form {
            BackupSettings()
            GeneralSettings(part: .retention)
            CaptureSettings(part: .rules)
            FoundOnThisMacSection()
            DataSettings(part: .importExport)
            DataSettings(part: .maintenance, hasStorage: hasStorage, onOpenInsights: { showingInsights = true })
            StartOverSettings()
        }
        .formStyle(.grouped)
        .settingsRowScrolling()
        .onAppear { appState.refreshInstalledImportSources() }
        .sheet(isPresented: $showingInsights) {
            insightsSheet
        }
        .settingsPaneTop {
            VStack(spacing: 0) {
                SettingsPaneHeader(
                    symbol: "externaldrive", title: "Data",
                    subtitle: Text("What Pesto keeps, for how long, and where your copies live.")
                )
                if hasStorage { DataStatStrip().padding(.horizontal, 20).padding(.bottom, 8) }
            }
        }
    }

    private var insightsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity insights").font(.headline)
                Spacer()
                Button("Done") { showingInsights = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.pestoProminent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            Divider()
            if let container = appState.historyContainer {
                Form {
                    HistoryLockGate { InsightsView() }
                }
                .formStyle(.grouped)
                .modelContainer(container)
            } else {
                Form {
                    HistoryLockGate { InsightsView() }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 560, height: 520)
    }
}

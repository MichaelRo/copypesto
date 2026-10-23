// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct GeneralPane: View {
    @Environment(AppState.self) private var appState: AppState

    var body: some View {
        Form {
            GeneralSettings(part: .startup)
            GeneralSettings(part: .copyPaste)
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
            PrivacySettings(part: .promise)
            CaptureSettings(part: .lock)
            ExclusionSettings()
            OtherDevicesSettings()
            PrivacySettings(part: .ignored)
            CaptureSettings(part: .sensitiveContent)
            CaptureSettings(part: .screenSharing)
            CaptureSettings(part: .outside)
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

    var body: some View {
        Form {
            GeneralSettings(part: .retention)
            CaptureSettings(part: .rules)
            BackupSettings()
            FoundOnThisMacSection()
            DataSettings(part: .importExport)
            DataSettings(part: .maintenance)
            if hasStorage { HistoryLockGate { InsightsView() } }
            StartOverSettings()
        }
        .formStyle(.grouped)
        .settingsRowScrolling()
        .onAppear { appState.refreshInstalledImportSources() }
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
}

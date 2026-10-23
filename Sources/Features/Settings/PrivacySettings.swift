// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What Pesto promises about your clips, what it has refused to keep, and how to wipe it. Numbers only: nothing here
/// shows clip content.
struct PrivacySettings: View {
    enum Part {
        case promise, ignored
    }

    let part: Part
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.pestoAccent) private var accent
    @AppStorage(AutoBackupSettings.enabledKey) private var autoBackup = false
    @State private var snapshot: PrivacySnapshot?
    @State private var stats = PrivacyStatsStore().stats

    var body: some View {
        Group {
            switch part {
            case .promise: promiseSection
            case .ignored: ignoredSection
            }
        }
        .task { await refresh() }
    }

    // MARK: - The promise

    private var promiseSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your clips stay on this Mac").font(.headline)
                    Text("The full list of what leaves it is on this pane.")
                        .font(.callout).pestoQuiet()
                }
            }
            .padding(.vertical, 4)
            .settingsRow("What stays on this Mac")
            .listRowBackground(LinearGradient(
                colors: [accent.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .trailing
            ))
            line(
                "lock", "Encryption",
                detail: (BlobEncryption.isKeyAvailable ? "" : "No key yet. ")
                    + String(localized: "AES-256-GCM, with the key in this Mac\u{2019}s Keychain."),
                id: "key"
            )
            .settingsRow("Encryption")
            DisclosureGroup("What stays readable") {
                Text(CaptureSettings.encryptionCaption).pestoCaption()
            }
            .padding(.leading, 58)
            line("internaldrive", "Uploads", detail: PrivacyNetworkFacts.clips, id: "net-clips")
            line("cpu", "AI features", detail: "Run on this Mac only", id: "net-ai")
            line("arrow.down.circle", "Update checks", detail: PrivacyNetworkFacts.updates, id: "net-updates")
            line(
                "externaldrive.badge.icloud", "Automatic backup",
                detail: PrivacyNetworkFacts.backup(
                    enabled: autoBackup,
                    automatic: AutoBackupSettings().runsAutomatically,
                    folder: AutoBackupSettings().folder
                ),
                id: "net-backup"
            )
        }
    }

    private func line(_ symbol: String, _ title: LocalizedStringKey, detail: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .pestoQuiet()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.privacyFact(id))
        }
    }

    // MARK: - Ignored copies

    private var ignoredSection: some View {
        Section {
            SettingsStatStrip(stats: [
                SettingsStat(id: "excluded", value: "\(stats.excludedAppBlocks)", label: "From excluded apps"),
                SettingsStat(id: "concealed", value: "\(stats.concealedBlocks)", label: "Marked private"),
                SettingsStat(id: "remote", value: "\(stats.remoteBlocks)", label: "From other devices")
            ])
        } header: {
            Text("Left out of your history")
        } footer: {
            if let since = stats.since {
                HStack {
                    Text(
                        "Counted since \(since.formatted(date: .abbreviated, time: .omitted)). " +
                            "Only counts are kept, never what was copied."
                    )
                    .pestoCaption()
                    Spacer()
                    Button("Reset Counts") {
                        PrivacyStatsStore().reset()
                        stats = PrivacyStatsStore().stats
                    }
                    .buttonStyle(.pestoLink)
                    .controlSize(.small)
                }
            }
        }
    }

    private func refresh() async {
        snapshot = await appState.privacySnapshot?()
        stats = PrivacyStatsStore().stats
    }
}

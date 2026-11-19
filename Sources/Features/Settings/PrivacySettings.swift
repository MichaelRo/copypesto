// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What Pesto promises about your clips and what it has refused to keep. Numbers only: nothing here shows clip content.
struct PrivacySettings: View {
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.pestoAccent) private var accent
    @AppStorage(AutoBackupSettings.enabledKey) private var autoBackup = false
    @State private var snapshot: PrivacySnapshot?
    @State private var stats = PrivacyStatsStore().stats
    @State private var showingDetails = false

    private var encryptionSummary: String {
        (BlobEncryption.isKeyAvailable ? "" : "No key yet. ")
            + String(localized: "AES-256-GCM, with the key in this Mac\u{2019}s Keychain.")
    }

    private var totalBlocked: Int {
        stats.excludedAppBlocks + stats.concealedBlocks + stats.remoteBlocks
    }

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text("Encrypted on this Mac").fontWeight(.medium)
                InfoPopoverButton("What stays readable", verbatimMessage: CaptureSettings.encryptionCaption)
                Spacer()
                Button("Details\u{2026}") { showingDetails = true }
                    .controlSize(.small)
            }
            .settingsRow("What stays on this Mac")

            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .foregroundStyle(accent)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                HStack(spacing: 6) {
                    Text("Encryption").fontWeight(.medium)
                    Text(encryptionSummary).pestoCaption()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.privacyFact("key"))
                Spacer()
            }
            .settingsRow("Encryption")

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    factCell("internaldrive", "Uploads", detail: PrivacyNetworkFacts.clips, id: "net-clips")
                    factCell("cpu", "AI features", detail: "Run on this Mac only", id: "net-ai")
                }
                GridRow {
                    factCell(
                        "arrow.down.circle",
                        "Update checks",
                        detail: PrivacyNetworkFacts.updates,
                        id: "net-updates"
                    )
                    factCell(
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
            .padding(.vertical, 2)
        } footer: {
            HStack(spacing: 8) {
                Text(
                    "Left out: \(stats.excludedAppBlocks) excluded \u{00B7} \(stats.concealedBlocks) private " +
                        "\u{00B7} \(stats.remoteBlocks) from other devices"
                )
                .pestoCaption()
                Spacer()
                if totalBlocked > 0 || stats.since != nil {
                    Button("Reset Counts") {
                        PrivacyStatsStore().reset()
                        stats = PrivacyStatsStore().stats
                    }
                    .buttonStyle(.pestoLink)
                    .controlSize(.small)
                }
            }
        }
        .task { await refresh() }
        .sheet(isPresented: $showingDetails) {
            PrivacyDetailsSheet(
                encryptionSummary: encryptionSummary,
                autoBackup: autoBackup,
                stats: $stats
            )
        }
    }

    private func factCell(_ symbol: String, _ title: LocalizedStringKey, detail: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .pestoCaption()
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.privacyFact(id))
    }

    private func refresh() async {
        snapshot = await appState.privacySnapshot?()
        stats = PrivacyStatsStore().stats
    }
}

private struct PrivacyDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pestoAccent) private var accent
    let encryptionSummary: String
    let autoBackup: Bool
    @Binding var stats: PrivacyStats

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your clips stay on this Mac").font(.headline)
                    Text("Everything Pesto encrypts, what leaves this Mac, and what stays readable.")
                        .pestoCaption()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Encryption & what stays readable").font(.subheadline.weight(.semibold))
                Text(encryptionSummary).font(.callout)
                Text(CaptureSettings.encryptionCaption).pestoCaption()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Network").font(.subheadline.weight(.semibold))
                detailRow("Uploads", detail: PrivacyNetworkFacts.clips)
                detailRow("AI features", detail: "Run on this Mac only")
                detailRow("Update checks", detail: PrivacyNetworkFacts.updates)
                detailRow(
                    "Automatic backup",
                    detail: PrivacyNetworkFacts.backup(
                        enabled: autoBackup,
                        automatic: AutoBackupSettings().runsAutomatically,
                        folder: AutoBackupSettings().folder
                    )
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Left out of your history").font(.subheadline.weight(.semibold))
                SettingsStatStrip(stats: [
                    SettingsStat(id: "excluded", value: "\(stats.excludedAppBlocks)", label: "From excluded apps"),
                    SettingsStat(id: "concealed", value: "\(stats.concealedBlocks)", label: "Marked private"),
                    SettingsStat(id: "remote", value: "\(stats.remoteBlocks)", label: "From other devices")
                ])
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

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.pestoProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func detailRow(_ title: LocalizedStringKey, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.callout.weight(.medium)).frame(width: 130, alignment: .leading)
            Text(detail).pestoCaption().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What goes where: a locked tick for what is always in the file or the log, and a real box for the one choice there
/// is for each, clips with secrets. The Sync column is there only when sync is on.
struct BackupContentsTable: View {
    @Environment(\.pestoAccent) private var accent
    let backupOn: Bool
    @Binding var backupSecrets: Bool
    var syncOn = false
    var syncSecrets: Binding<Bool>?
    var keepsHere = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            row("Clips, with their pins")
            row("Collections")
            row("Snippets")
            secretsRow
            row("This Mac\u{2019}s settings", detail: "Shortcuts, ignored apps", syncAlways: false)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What goes where")
    }

    private var header: some View {
        HStack {
            Text("What goes where").font(.callout.weight(.semibold))
            Spacer()
            Text("Backup").font(.callout.weight(.semibold)).frame(width: 90)
            if syncOn { Text("Sync").font(.callout.weight(.semibold)).frame(width: 90) }
        }
        .padding(.bottom, 6)
    }

    private func row(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        syncAlways: Bool = true
    )
    -> some View {
        HStack {
            titleBlock(title, detail)
            Spacer()
            tick(on: backupOn)
            if syncOn {
                if syncAlways { tick(on: true) } else { Text("\u{2013}").pestoQuiet().frame(width: 90) }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func titleBlock(_ title: LocalizedStringKey, _ detail: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            if let detail { Text(detail).font(.caption).pestoQuiet() }
        }
    }

    private func tick(on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(on ? accent : Color.primary.opacity(0.12))
            .frame(width: 18, height: 18)
            .overlay(
                Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white).opacity(on ? 1 : 0)
            )
            .frame(width: 90)
            .accessibilityLabel(on ? "Included" : "Not included")
    }

    private var secretsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Clips with secrets")
                Text(syncOn && keepsHere > 0 ? "\(keepsHere) clips stay on this Mac" : "Card numbers, keys, tokens")
                    .font(.caption).pestoQuiet()
            }
            Spacer()
            Toggle("Include clips with secrets in the backup", isOn: $backupSecrets)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 90)
                .accessibilityIdentifier(AccessibilityID.backupIncludesSecretsToggle)
            if syncOn, let syncSecrets {
                Toggle("Include clips with secrets in sync", isOn: syncSecrets)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 90)
                    .accessibilityIdentifier(AccessibilityID.syncSecretsToggle)
            }
        }
        .padding(.vertical, 5)
    }
}

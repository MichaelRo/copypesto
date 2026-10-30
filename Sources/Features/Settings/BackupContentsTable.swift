// SPDX-License-Identifier: MIT
import SwiftUI

/// What the backup holds, in the same table the sync column will join: a locked tick for what is always in the file,
/// and a real box for the one choice there is, clips with secrets.
struct BackupContentsTable: View {
    @Environment(\.pestoAccent) private var accent
    @Binding var includesSecrets: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            row("Clips, with their pins")
            row("Collections")
            row("Snippets")
            secretsRow
            row("This Mac\u{2019}s settings", detail: "Shortcuts, ignored apps")
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
        }
        .padding(.bottom, 6)
    }

    private func row(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil) -> some View {
        HStack {
            titleBlock(title, detail)
            Spacer()
            lockedTick
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

    private var lockedTick: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(accent)
            .frame(width: 18, height: 18)
            .overlay(Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white))
            .frame(width: 90)
            .accessibilityLabel("Always included")
    }

    private var secretsRow: some View {
        HStack {
            titleBlock("Clips with secrets", "Card numbers, keys, tokens")
            Spacer()
            Toggle("Include clips with secrets in the backup", isOn: $includesSecrets)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 90)
                .accessibilityIdentifier(AccessibilityID.backupIncludesSecretsToggle)
        }
        .padding(.vertical, 5)
    }
}

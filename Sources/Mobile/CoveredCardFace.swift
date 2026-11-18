// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A covered card: a secret shows only its mask, a lock and its category, with an eye that asks to Show; anything else
/// covered shows only its kind. Nothing of the content is drawn (ADR 0003).
struct CoveredCardFace: View {
    let item: ClipboardItem
    let isSecret: Bool
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: CardMetrics.footGap) {
            if isSecret { secretBody } else { coveredBody }
            CardFootLineView(item: item, trailingMark: isSecret ? item.sensitivity?.badgeLabel : nil)
        }
        .padding(CardMetrics.inset)
    }

    private var secretBody: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            Text(item.gridPreview)
                .font(.callout.monospaced())
                .lineLimit(3)
            Spacer(minLength: 4)
            if appState.secretReveal.canAuthenticate {
                Button("Show", systemImage: "eye") { show() }
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                    .contentShape(.rect)
                    .padding(.top, -2)
                    .padding(.trailing, -4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var coveredBody: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash.fill").font(.title2)
            Text(item.type.presentation.label).font(.caption.weight(.medium))
            if appState.secretReveal.isCoveredForPrivacy(item.id) {
                Button("Show") { appState.secretReveal.showUnderCover(item.id) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(MobileAccessibilityID.showUnderCoverButton)
            } else if item.isNSFW {
                Text("Sensitive content").font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func show() {
        let id = item.id
        Task { await appState.secretReveal.show(id, reason: String(localized: "Show the hidden clip")) }
    }
}

struct SecretShownBody: View {
    let item: ClipboardItem
    let text: String?
    let metrics: CardMetrics
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(text ?? item.gridPreview)
                .font(.footnote.monospaced())
                .lineLimit(metrics.lines(.footnote))
                .textSelection(.disabled)
            Spacer(minLength: 4)
            Button("Hide", systemImage: "eye.slash") { appState.secretReveal.hide(item.id) }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                .contentShape(.rect)
                .padding(.top, -12)
                .padding(.trailing, -6)
        }
    }
}

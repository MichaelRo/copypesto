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
            ItemFootLineView(item: item, trailingMark: isSecret ? item.sensitivity?.badgeLabel : nil)
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
        Group {
            if appState.secretReveal.isCoveredForPrivacy(item.id) {
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill").font(.title2)
                    Text(item.type.presentation.label).font(.caption.weight(.medium))
                    Button("Show") { appState.secretReveal.showUnderCover(item.id) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(CoverShowStyle())
                        .accessibilityIdentifier(MobileAccessibilityID.showUnderCoverButton)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if item.isNSFW {
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill").font(.title2)
                    Text(item.type.presentation.label).font(.caption.weight(.medium))
                    Text("Sensitive content").font(.caption)
                    Button("Show") { appState.secretReveal.showNSFW(item.id) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(CoverShowStyle())
                        .accessibilityIdentifier(MobileAccessibilityID.showSensitiveButton)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if item.analysisPending {
                PendingImageBody()
            }
        }
    }

    private func show() {
        let id = item.id
        Task { await appState.secretReveal.show(id, reason: String(localized: "Show the hidden clip")) }
    }
}

private struct PendingImageBody: View {
    @State private var shimmerOffset: CGFloat = -1

    private let wellShape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        ZStack {
            wellShape
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    if !Motion.reduceMotion {
                        GeometryReader { proxy in
                            LinearGradient(
                                colors: [.clear, Color.primary.opacity(0.045), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: proxy.size.width * 1.4)
                            .offset(x: shimmerOffset * proxy.size.width * 1.4)
                            .onAppear {
                                withAnimation(Motion.animation(.pestoWash)?.repeatForever(autoreverses: false)) {
                                    shimmerOffset = 1
                                }
                            }
                        }
                        .clipShape(wellShape)
                    }
                }
                .overlay(wellShape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary.opacity(0.6))

                HStack(spacing: 5) {
                    if !Motion.reduceMotion {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text("Checking image\u{2026}")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// The small bordered Show of a covered card, with a 44 point hit area around it.
private struct CoverShowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.18 : 0.10)))
            .foregroundStyle(.primary)
            .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
            .contentShape(.rect)
    }
}

struct SecretShownBody: View {
    let item: ClipboardItem
    let text: String?
    let metrics: CardMetrics
    var hasTitle = false
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(text ?? item.gridPreview)
                .font(.footnote.monospaced())
                .lineLimit(metrics.lines(.footnote, hasTitle: hasTitle))
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

// SPDX-License-Identifier: MIT
import SwiftUI

struct ShelfBannerCapsule: View {
    struct Action {
        let title: LocalizedStringKey
        let identifier: String
        let perform: () -> Void
    }

    static let height: CGFloat = 30

    let symbol: String
    let message: String
    let primary: Action
    var secondary: Action?
    var onDismiss: (() -> Void)?

    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(message)
                .scaledFont(size: 11)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(message)
            Button(primary.title, action: primary.perform)
                .buttonStyle(.pestoCapsule(.primary))
                .fixedSize()
                .accessibilityIdentifier(primary.identifier)
            if let secondary {
                Button(secondary.title, action: secondary.perform)
                    .buttonStyle(.pestoCapsule(.secondary))
                    .fixedSize()
                    .accessibilityIdentifier(secondary.identifier)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(AdaptiveContrast.quiet(contrast))
                        .pestoHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, onDismiss == nil ? 3 : 10)
        .frame(height: Self.height)
        .shelfCapsuleChrome()
    }
}

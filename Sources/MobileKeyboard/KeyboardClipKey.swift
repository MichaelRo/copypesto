// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// One clip on the keyboard, drawn as a small Pesto card: the iOS library's fill, corner and hairline, the text on
/// top and a foot line with the kind's glyph, as the cards on the Mac and in the app end.
struct KeyboardClipKey: View {
    let entry: QuickInsertEntry
    let isInserted: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private static let cornerRadius: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.label())
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: isInserted ? "checkmark" : Self.symbol(of: entry))
                    .foregroundStyle(isInserted ? BrandAccent.color : .secondary)
                Text(Self.footLabel(of: entry))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption2)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(colorScheme == .dark ? Color.white.opacity(0.10) : .white, in: shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.45 : 0.14), lineWidth: 0.75) }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.label())
        .accessibilityValue(Text(Self.footLabel(of: entry)))
        .accessibilityHint(Text("Inserts this clip and returns to your keyboard"))
        .accessibilityAddTraits(.isButton)
    }

    static func title(of section: QuickInsertEntry.Section) -> String {
        switch section {
        case .pinned: String(localized: "Pinned")
        case .snippets: String(localized: "Snippets")
        case .recent: String(localized: "Recent")
        }
    }

    private static func symbol(of entry: QuickInsertEntry) -> String {
        entry.expandsOnInsert ? "text.badge.plus" : entry.kind.presentation.symbolName
    }

    private static func footLabel(of entry: QuickInsertEntry) -> String {
        entry.expandsOnInsert ? String(localized: "Snippet") : entry.kind.presentation.label
    }
}

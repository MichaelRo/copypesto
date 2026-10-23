// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Reusable emoji picker popover with keyword suggestions and a quick-pick grid.
/// Used by both CollectionEditor (Settings sheet) and CollectionEditPopover (overlay).
struct EmojiPickerPopover: View {
    @Environment(\.pestoAccent) private var accent
    var name: String
    var selectedEmoji: String?
    var onSelect: (String) -> Void
    var onOpenSystem: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let suggestions = suggestedEmojis(for: name)
            if !suggestions.isEmpty {
                Text("Suggested")
                    .scaledFont(size: 10, weight: .semibold)
                    .pestoQuiet()
                HStack(spacing: 4) {
                    ForEach(suggestions, id: \.self) { emoji in
                        emojiButton(emoji)
                    }
                }
            }

            Text("Quick picks")
                .scaledFont(size: 10, weight: .semibold)
                .pestoQuiet()
            let rows = quickEmojis.chunked(into: 8)
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(rows[row], id: \.self) { emoji in
                        emojiButton(emoji)
                    }
                }
            }

            Divider()

            Button {
                onOpenSystem()
            } label: {
                Label("More Emojis…", systemImage: "face.smiling")
                    .scaledFont(size: 11)
                    .pestoQuiet()
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(minWidth: 200)
    }

    private func emojiButton(_ emoji: String) -> some View {
        Button {
            onSelect(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 18))
                .padding(3)
                .background(
                    selectedEmoji == emoji ? accent.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
        .buttonStyle(.plain)
        .help(emoji)
    }

    private let quickEmojis = [
        "📁", "⭐️", "🔥", "💡", "🎯", "📌", "🎨", "🚀",
        "💼", "📚", "🛍️", "🏠", "💻", "🔧", "🌍", "🎵",
        "✅", "📝", "🔑", "💬", "📷", "🎭", "🍕", "🏋️"
    ]

    private func suggestedEmojis(for name: String) -> [String] {
        let lower = name.lowercased()
        if lower.contains("work") || lower.contains("job") || lower
            .contains("office") { return ["💼", "📋", "🗂️", "🏢", "⚡️"] }
        if lower.contains("code") || lower.contains("dev") || lower.contains("tech") || lower.contains("swift") {
            return ["💻", "⌨️", "🔧", "🛠️", "⚙️"]
        }
        if lower.contains("design") || lower.contains("art") || lower
            .contains("ui") { return ["🎨", "✏️", "🖌️", "💎", "🎭"] }
        if lower.contains("read") || lower.contains("book") || lower
            .contains("study") { return ["📚", "📖", "🎓", "📝", "🔬"] }
        if lower.contains("shop") || lower.contains("buy") || lower
            .contains("cart") { return ["🛍️", "🛒", "💳", "🏷️", "📦"] }
        if lower.contains("personal") || lower.contains("home") || lower.contains("family") { return [
            "🏠",
            "❤️",
            "👨‍👩‍👧",
            "🌟",
            "🌿"
        ] }
        if lower.contains("travel") || lower.contains("trip") || lower.contains("vacation") { return [
            "✈️",
            "🗺️",
            "🏖️",
            "🌍",
            "🧳"
        ] }
        if lower.contains("food") || lower.contains("cook") || lower.contains("recipe") { return [
            "🍕",
            "🍳",
            "🥗",
            "🍜",
            "🧁"
        ] }
        if lower.contains("health") || lower.contains("fitness") || lower.contains("gym") { return [
            "🏋️",
            "🏃",
            "💪",
            "🧘",
            "🍎"
        ] }
        if lower.contains("music") || lower.contains("audio") || lower.contains("podcast") { return [
            "🎵",
            "🎸",
            "🎧",
            "🎤",
            "🎼"
        ] }
        if lower.contains("project") || lower.contains("task") || lower.contains("todo") { return [
            "✅",
            "📋",
            "🎯",
            "📌",
            "🗓️"
        ] }
        return []
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

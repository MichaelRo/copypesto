// SPDX-License-Identifier: MIT
public enum CollectionSymbol {
    /// A collection icon is either an SF Symbol name or an emoji; digits and `#` are emoji-capable scalars but not
    /// emoji.
    public static func isEmoji(_ symbol: String) -> Bool {
        symbol.unicodeScalars.first.map { $0.properties.isEmoji && $0.value > 0x238C } ?? false
    }
}

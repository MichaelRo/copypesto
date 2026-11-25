// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import Synchronization

/// The first colour literal in a card's text (or whole-string color value for `.color` clips), as a SwiftUI colour.
enum ColorStringDetector {
    private static let capacity = 4000
    private static let remembered = Mutex<[String: HexColorComponents?]>([:])
    private static let rememberedWhole = Mutex<[String: HexColorComponents?]>([:])

    /// A card asks on every redraw, and each ask runs pattern matches, so the answer is kept per text.
    static func components(in text: String) -> HexColorComponents? {
        if let known = remembered.withLock({ $0[text] }) { return known }
        let found = ColorLiteralParser.firstColor(in: text)
        remembered.withLock {
            if $0.count >= capacity { $0.removeAll(keepingCapacity: true) }
            $0[text] = .some(found)
        }
        return found
    }

    static func wholeComponents(in text: String) -> HexColorComponents? {
        if let known = rememberedWhole.withLock({ $0[text] }) { return known }
        let found = ColorLiteralParser.color(fromWholeString: text)
        rememberedWhole.withLock {
            if $0.count >= capacity { $0.removeAll(keepingCapacity: true) }
            $0[text] = .some(found)
        }
        return found
    }

    static func detect(in text: String) -> Color? {
        components(in: text).map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) }
    }

    static func detectWholeColor(in text: String) -> Color? {
        wholeComponents(in: text).map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) }
    }
}

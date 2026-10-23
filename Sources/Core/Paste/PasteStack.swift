// SPDX-License-Identifier: MIT
import Foundation

/// An ordered, ephemeral queue of clipboard payloads for sequential pasting.
///
/// The user builds a stack by selecting multiple cards in the overlay.
/// Each ⌘⇧V press (while a stack is active) pastes `current` and calls `advance()`.
/// When `isComplete`, the stack is discarded and the HUD is dismissed.
public struct PasteStack: Sendable {
    /// A single entry in the paste queue.
    public struct Item: Sendable {
        /// Short preview shown in the stack HUD.
        public let previewText: String
        /// Payload kind forwarded to `PasteCoordinator.executePaste`.
        public let payloadKind: PasteCoordinator.PayloadKind
        /// Raw bytes written to `NSPasteboard`. Nil means use `previewText` as `.string`.
        public let pasteboardData: Data?
        /// Pasteboard type string paired with `pasteboardData`. Nil when data is nil.
        public let pasteboardType: String?
        /// Formatted flavours (RTF, RTFD, HTML) paired with a plain-text stack item.
        public let richPayload: RichTextPayload?
        /// True when the clip holds a secret, so writing it back keeps it off Universal Clipboard and out of other
        /// clipboard managers.
        public let isProtected: Bool

        public init(
            previewText: String,
            payloadKind: PasteCoordinator.PayloadKind,
            pasteboardData: Data? = nil,
            pasteboardType: String? = nil,
            richPayload: RichTextPayload? = nil,
            isProtected: Bool = false
        ) {
            self.previewText = previewText
            self.payloadKind = payloadKind
            self.pasteboardData = pasteboardData
            self.pasteboardType = pasteboardType
            self.richPayload = richPayload
            self.isProtected = isProtected
        }
    }

    /// A stack decrypts every clip it holds when it is made and keeps the plaintext until it is spent, so select-all
    /// cannot build one over a whole history.
    public static let maxItems = 100

    /// The most plaintext a stack holds at once; the first clip is always kept, whatever its size.
    public static let maxTotalBytes = 50 * 1_048_576

    /// The first clips of `selection` that fit `maxItems` and `maxTotalBytes`, and how many were left out.
    public static func limited<Element>(
        _ selection: [Element], byteSize: (Element) -> Int
    )
    -> (kept: [Element], leftOut: Int) {
        var kept: [Element] = []
        var total = 0
        for element in selection.prefix(maxItems) {
            if !kept.isEmpty, total + byteSize(element) > maxTotalBytes { break }
            total += byteSize(element)
            kept.append(element)
        }
        return (kept, selection.count - kept.count)
    }

    /// The first `maxItems` of `selection` and how many were left out.
    public static func limited<Element>(_ selection: [Element]) -> (kept: [Element], leftOut: Int) {
        (Array(selection.prefix(maxItems)), max(0, selection.count - maxItems))
    }

    public private(set) var items: [Item]
    public private(set) var currentIndex: Int

    public var count: Int {
        items.count
    }

    /// The item to paste next, or `nil` when the stack is exhausted.
    public var current: Item? {
        isComplete ? nil : items[currentIndex]
    }

    /// `true` once all items have been pasted.
    public var isComplete: Bool {
        currentIndex >= items.count
    }

    /// "2/5" label for the HUD showing which item is up next.
    public var progressLabel: String {
        "\(currentIndex + 1)/\(items.count)"
    }

    public init(items: [Item]) {
        precondition(!items.isEmpty, "PasteStack requires at least one item")
        self.items = items
        self.currentIndex = 0
    }

    /// Moves to the next item. No-ops when already complete.
    public mutating func advance() {
        if currentIndex < items.count {
            currentIndex += 1
        }
    }
}

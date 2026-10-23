// SPDX-License-Identifier: MIT
import Foundation

/// What the hover popover shows for a clip. It used to show content only for code (and text that looked like
/// Markdown), so most cards opened a box of metadata and nothing else.
public enum DetailPopoverContent {
    public enum Body: Equatable, Sendable {
        case text
        case markdown
        case code
        case link
        case picture
        case files
        case color
        /// A secret: only what is known about it. The popover never reads its text, masked or not.
        case metadataOnly
    }

    /// The popover scrolls past this, and the card's own preview is 500 characters.
    public static let maxCharacters = 4000
    /// The popover decrypts a clip on the main thread when it opens, so a very large one is not read for it.
    public static let maxReadableBytes = 1_000_000

    public static func body(type: ClipboardType, isSensitive: Bool, text: String) -> Body {
        if isSensitive { return .metadataOnly }
        switch type {
        case .text: return looksLikeMarkdown(text) ? .markdown : .text
        case .code: return .code
        case .url: return .link
        case .image: return .picture
        case .file: return .files
        case .color: return .color
        }
    }

    public static func looksLikeMarkdown(_ text: String) -> Bool {
        text.contains("**") || text.contains("# ") || text.contains("- ") || text.contains("```") ||
            text.contains("[") || text.contains("_")
    }

    public static func shown(_ text: String) -> (text: String, wasCut: Bool) {
        guard let end = text.index(text.startIndex, offsetBy: maxCharacters, limitedBy: text.endIndex),
              end != text.endIndex else { return (text, false) }
        return (String(text[..<end]), true)
    }

    public static func canRead(byteSize: Int) -> Bool {
        byteSize <= maxReadableBytes
    }

    public struct RGB: Equatable, Sendable {
        public let red: Int
        public let green: Int
        public let blue: Int

        public init(red: Int, green: Int, blue: Int) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public struct FactsInput: Sendable {
        public let type: ClipboardType
        /// Set for a secret: its kind, and nothing else about it is said.
        public let secretKind: String?
        public let isRemote: Bool
        public let copiedAt: Date
        public let byteSize: Int
        /// The whole clip's length; 0 for a clip captured before it was stored.
        public let characterCount: Int
        public let shownText: String
        public let wasCut: Bool
        public let language: String?
        public let fileCount: Int
        public let rgb: RGB?
        public let collectionName: String?
        public let pixelWidth: Int?
        public let pixelHeight: Int?
        public let pasteCount: Int

        public init(
            type: ClipboardType, secretKind: String?, isRemote: Bool, copiedAt: Date, byteSize: Int,
            characterCount: Int, shownText: String, wasCut: Bool, language: String?, fileCount: Int, rgb: RGB?,
            collectionName: String?, pixelWidth: Int? = nil, pixelHeight: Int? = nil, pasteCount: Int = 0
        ) {
            self.type = type
            self.secretKind = secretKind
            self.isRemote = isRemote
            self.copiedAt = copiedAt
            self.byteSize = byteSize
            self.characterCount = characterCount
            self.shownText = shownText
            self.wasCut = wasCut
            self.language = language
            self.fileCount = fileCount
            self.rgb = rgb
            self.collectionName = collectionName
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.pasteCount = pasteCount
        }
    }

    /// The line under the card's body: when, then what fits the type, then the collection. The source app is not
    /// here (the card below names it), except for a clip from another device.
    public static func facts(_ input: FactsInput) -> [DetailFact] {
        var facts: [DetailFact] = []
        if input.isRemote { facts.append(.fromPhone) }
        facts.append(.copied(input.copiedAt))
        if let kind = input.secretKind {
            facts.append(.secretKind(kind))
        } else {
            facts.append(contentsOf: measure(of: input))
        }
        if let name = input.collectionName, !name.isEmpty { facts.append(.collection(name)) }
        if input.pasteCount > 0 { facts.append(.pasteCount(input.pasteCount)) }
        return facts
    }

    private static func measure(of input: FactsInput) -> [DetailFact] {
        switch input.type {
        case .text:
            return [lengthFact(input)]
        case .code:
            var facts: [DetailFact] = []
            if let language = input.language, !language.isEmpty { facts.append(.language(language)) }
            facts.append(input.wasCut ? lengthFact(input) : .lines(TextLines.count(in: input.shownText)))
            return facts
        case .url:
            return []
        case .image:
            var facts: [DetailFact] = []
            if let width = input.pixelWidth, let height = input.pixelHeight, width > 0, height > 0 {
                facts.append(.dimensions(width: width, height: height))
            }
            facts.append(.bytes(input.byteSize))
            return facts
        case .file:
            return (input.fileCount > 0 ? [.files(input.fileCount)] : []) + [.bytes(input.byteSize)]
        case .color:
            return input.rgb.map { [.rgb(red: $0.red, green: $0.green, blue: $0.blue)] } ?? []
        }
    }

    private static func lengthFact(_ input: FactsInput) -> DetailFact {
        let total = input.characterCount > 0 ? input.characterCount : input.shownText.count
        return input.wasCut ? .charactersShown(shown: maxCharacters, total: total) : .characters(total)
    }
}

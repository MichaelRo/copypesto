// SPDX-License-Identifier: MIT
import PestoCore

/// The copy actions a clip's menus offer besides Copy, decided from what the clip is, as the Mac's context menu does:
/// nothing for a secret or a covered, filtered or still-judged clip (ADR 0003), the Mac's text transforms for text,
/// code and links, the color formats for a color, Copy Recognized Text and Save to Photos for a picture. A secret
/// offers one thing: Decode JWT, on a token, after the same authentication as Show (ADR 0020).
enum CardCopyActions {
    struct Facts: Equatable {
        let type: ClipboardType
        let isSecret: Bool
        let isCovered: Bool
        let isFiltered: Bool
        let isPending: Bool
        let hasColor: Bool
        let offersRecognizedText: Bool
        var isJWT = false
        var allowsDecode = false
        var canAuthenticate = false
        /// What `StructuredPaste` says the clip qualifies for, worked out by the caller when the menu opens.
        var structured: [TextTransform] = []
    }

    struct Offer: Equatable {
        var structured: [TextTransform] = []
        var transforms: [TextTransform] = []
        var colorFormats: [ColorCopyFormat] = []
        var offersRecognizedText = false
        var offersSaveToPhotos = false
        var offersDecodeJWT = false

        var isEmpty: Bool {
            structured.isEmpty && transforms.isEmpty && colorFormats.isEmpty && !offersRecognizedText
                && !offersSaveToPhotos && !offersDecodeJWT
        }
    }

    static func offer(for facts: Facts) -> Offer {
        if facts.isSecret {
            return Offer(offersDecodeJWT: facts.isJWT && facts.allowsDecode && facts.canAuthenticate)
        }
        guard !facts.isCovered, !facts.isFiltered, !facts.isPending else { return Offer() }
        switch facts.type {
        case .text, .code, .url:
            return Offer(structured: facts.structured, transforms: TextTransform.available(for: facts.type))
        case .color:
            return Offer(colorFormats: facts.hasColor ? ColorCopyFormat.allCases : [])
        case .image:
            return Offer(offersRecognizedText: facts.offersRecognizedText, offersSaveToPhotos: true)
        case .file:
            return Offer()
        }
    }
}

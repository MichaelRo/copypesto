// SPDX-License-Identifier: MIT
import Foundation

public enum ClipboardType: String, Codable, Sendable, CaseIterable {
    case text
    case url
    case image
    case file
    case color
    case code

    /// The language name of a code clip that is an SVG picture's source.
    public static let svgLanguage = "SVG"
    public static let markdownLanguage = "markdown"
}

public extension ClipboardType {
    /// One vocabulary for the card badge and the filter chip.
    var presentation: (label: String, symbolName: String) {
        switch self {
        case .text: (String(localized: "Text"), "text.alignleft")
        case .url: (String(localized: "Link"), "link")
        case .image: (String(localized: "Image"), "photo")
        case .file: (String(localized: "File"), "doc")
        case .color: (String(localized: "Color"), "paintpalette")
        case .code: (String(localized: "Code"), "chevron.left.forwardslash.chevron.right")
        }
    }
}

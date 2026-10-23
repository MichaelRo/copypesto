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
        case .text: ("Text", "text.alignleft")
        case .url: ("Link", "link")
        case .image: ("Image", "photo")
        case .file: ("File", "doc")
        case .color: ("Color", "paintpalette")
        case .code: ("Code", "chevron.left.forwardslash.chevron.right")
        }
    }
}

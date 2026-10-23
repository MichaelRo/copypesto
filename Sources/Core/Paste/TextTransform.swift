// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// A text transformation applied to a clipboard item's content at paste time.
/// Each case maps 1-to-1 to an option in the "Paste as…" context-menu submenu.
public enum TextTransform: String, CaseIterable, Sendable {
    case stripFormatting = "Plain Text"
    case uppercase = "UPPERCASE"
    case lowercase
    case titleCase = "Title Case"
    case sentenceCase = "Sentence Case"
    case trimWhitespace = "Trim Whitespace"
    case unwrapLines = "Unwrap Lines"
    case removeDuplicateLines = "Remove Duplicate Lines"
    case sortLinesAZ = "Sort Lines A→Z"
    case sortLinesZA = "Sort Lines Z→A"
    case reverseLines = "Reverse Lines"
    case jsonPrettyPrint = "JSON Pretty-Print"
    case jsonMinify = "JSON Minify"
    case stripHTML = "Strip HTML Tags"
    case base64Encode = "Base64 Encode"
    case base64Decode = "Base64 Decode"
    case urlEncode = "URL Encode"
    case urlDecode = "URL Decode"
    case removeTrackingParams = "Remove Tracking Parameters"
    case slugCase = "Slug-Case"
    case camelCase
    case pascalCase = "PascalCase"
    case sha256Hash = "SHA-256 Hash"
    case md5Hash = "MD5 Hash"
    /// URL-specific: formats as a Markdown inline link `[url](url)`.
    case urlMarkdownLink = "Markdown Link"
    /// Code-specific: wraps the snippet in a triple-backtick fence.
    case markdownCodeBlock = "Markdown Code Block"

    public var symbolName: String {
        switch self {
        case .stripFormatting: "textformat.alt"
        case .uppercase: "textformat.size.larger"
        case .lowercase: "textformat.size.smaller"
        case .titleCase: "textformat"
        case .sentenceCase: "textformat.abc"
        case .trimWhitespace: "text.badge.minus"
        case .unwrapLines: "arrow.left.and.right"
        case .removeDuplicateLines: "line.3.horizontal.decrease"
        case .sortLinesAZ: "arrow.up.doc"
        case .sortLinesZA: "arrow.down.doc"
        case .reverseLines: "arrow.up.arrow.down"
        case .jsonPrettyPrint: "curlybraces"
        case .jsonMinify: "curlybraces.square"
        case .stripHTML: "chevron.left.forwardslash.chevron.right"
        case .base64Encode: "lock.doc"
        case .base64Decode: "lock.open.doc"
        case .urlEncode: "link"
        case .urlDecode: "link.badge.plus"
        case .removeTrackingParams: "line.diagonal.arrow"
        case .slugCase: "minus"
        case .camelCase: "character.cursor.ibeam"
        case .pascalCase: "textformat.abc.dottedunderline"
        case .sha256Hash: "checkmark.shield"
        case .md5Hash: "number.square"
        case .urlMarkdownLink: "link.badge.plus"
        case .markdownCodeBlock: "chevron.left.forwardslash.chevron.right"
        }
    }

    public func apply(to text: String) -> String {
        switch self {
        case .stripFormatting, .uppercase, .lowercase, .titleCase, .sentenceCase,
             .trimWhitespace, .unwrapLines, .removeDuplicateLines,
             .sortLinesAZ, .sortLinesZA, .reverseLines:
            applyCaseOrLine(to: text)
        case .jsonPrettyPrint, .jsonMinify, .stripHTML,
             .base64Encode, .base64Decode, .urlEncode, .urlDecode, .removeTrackingParams:
            applyEncodeOrFormat(to: text)
        case .slugCase, .camelCase, .pascalCase:
            applyWordCase(to: text)
        case .sha256Hash, .md5Hash:
            applyHash(to: text)
        case .urlMarkdownLink:
            "[\(text)](\(text))"
        case .markdownCodeBlock:
            "```\n\(text)\n```"
        }
    }

    /// Variant that injects the detected language into a markdown code fence.
    public func apply(to text: String, language: String?) -> String {
        guard self == .markdownCodeBlock, let lang = language, !lang.isEmpty else {
            return apply(to: text)
        }
        return "```\(lang)\n\(text)\n```"
    }

    private func applyCaseOrLine(to text: String) -> String {
        switch self {
        case .stripFormatting: return text
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .titleCase: return text.titleCased()
        case .sentenceCase: return text.sentenceCased()
        case .trimWhitespace: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .unwrapLines:
            return text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .removeDuplicateLines:
            var seen = Set<String>()
            return text.components(separatedBy: "\n")
                .filter { seen.insert($0).inserted }
                .joined(separator: "\n")
        case .sortLinesAZ:
            return text.components(separatedBy: "\n").sorted().joined(separator: "\n")
        case .sortLinesZA:
            return text.components(separatedBy: "\n").sorted().reversed().joined(separator: "\n")
        case .reverseLines:
            return text.components(separatedBy: "\n").reversed().joined(separator: "\n")
        default: return text
        }
    }

    private func applyEncodeOrFormat(to text: String) -> String {
        switch self {
        case .jsonPrettyPrint:
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(
                      withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                  ),
                  let result = String(data: pretty, encoding: .utf8) else { return text }
            return result
        case .jsonMinify:
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let minified = try? JSONSerialization.data(
                      withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]
                  ),
                  let result = String(data: minified, encoding: .utf8) else { return text }
            return result
        case .stripHTML: return text.strippingHTMLTags()
        case .base64Encode: return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
                  let decoded = String(data: data, encoding: .utf8) else { return text }
            return decoded
        case .urlEncode: return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        case .urlDecode: return text.removingPercentEncoding ?? text
        case .removeTrackingParams: return TrackingParameters.removed(from: text)
        default: return text
        }
    }

    private func applyWordCase(to text: String) -> String {
        switch self {
        case .slugCase: text.toSlugCase()
        case .camelCase: text.toCamelCase()
        case .pascalCase: text.toPascalCase()
        default: text
        }
    }

    private func applyHash(to text: String) -> String {
        let data = Data(text.utf8)
        switch self {
        case .sha256Hash:
            return data.sha256Hex
        case .md5Hash:
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        default: return text
        }
    }
}

private extension String {
    func titleCased() -> String {
        components(separatedBy: .whitespaces)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func sentenceCased() -> String {
        guard let first else { return self }
        return first.uppercased() + lowercased().dropFirst()
    }

    func strippingHTMLTags() -> String {
        var result = self
        while let open = result.range(of: "<"),
              let close = result.range(of: ">", range: open.upperBound..<result.endIndex)
        {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return result
    }

    func toSlugCase() -> String {
        lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    func toCamelCase() -> String {
        let words = wordsSplit()
        guard let first = words.first else { return self }
        return first.lowercased() + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined()
    }

    func toPascalCase() -> String {
        wordsSplit()
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined()
    }

    func wordsSplit() -> [String] {
        components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
    }
}

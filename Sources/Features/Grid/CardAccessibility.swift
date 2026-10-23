// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// What VoiceOver says about a clip card. The label is stable ("link from Safari: the text") because automation and
/// tests find cards by it; everything else a sighted person can see on the card goes in the value.
struct CardAccessibility {
    let type: ClipboardType
    let sourceName: String?
    /// Already masked for secrets and already turned into a file description for file clips.
    let preview: String
    let isHiddenSensitive: Bool
    let isPinned: Bool
    let hotkeySlot: Int?
    let burnsAfterPaste: Bool
    let expiresAt: Date?
    let tags: [String]
    let collectionName: String?
    let isRemote: Bool
    let age: TimeInterval
    let isSelected: Bool
    /// The name the person gave the clip, if any.
    var title: String?
    /// Set for a clip masked as a secret: VoiceOver says what kind it is, and the mask without the dots.
    var secretCategory: SensitivityCategory?

    var label: String {
        let source = sourceName.map { " from \($0)" } ?? ""
        if isHiddenSensitive { return "\(typeName)\(source): sensitive content, hidden" }
        if let secretCategory {
            return "\(typeName)\(source): \(Self.categoryName(secretCategory)), \(Self.spokenMask(preview))"
        }
        let text = String(preview.prefix(120)).replacingOccurrences(of: "\n", with: " ")
        return "\(typeName)\(source): \(text)"
    }

    /// A mask drawn as dots is read one dot at a time; it is "hidden" instead, and what the mask keeps (the last four
    /// digits, a key's prefix, "45 characters hidden") is still said.
    static func spokenMask(_ mask: String) -> String {
        let withoutDots = mask.replacingOccurrences(
            of: "[•\\s]*•[•\\s]*", with: " hidden ", options: .regularExpression
        )
        let words = withoutDots.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.isEmpty ? "hidden" : words
    }

    static func categoryName(_ category: SensitivityCategory) -> String {
        switch category {
        case .creditCard: "card number"
        case .ssn: "social security number"
        case .jwt: "token"
        case .apiKey: "API key"
        case .oauthToken: "access token"
        case .privateKey: "private key"
        case .password: "password"
        case .credential: "credential"
        }
    }

    var value: String {
        var parts: [String] = []
        if let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty { parts.append("named \(title)") }
        if isPinned { parts.append("pinned") }
        if let hotkeySlot { parts.append("control \(hotkeySlot)") }
        if burnsAfterPaste { parts.append("burns after paste") }
        if let expiresAt, !burnsAfterPaste {
            parts.append("expires \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if !tags.isEmpty { parts.append(String(localized: "tags \(tags.count) \(Self.list(tags))")) }
        if let collectionName { parts.append("in \(collectionName)") }
        if isRemote { parts.append("from another device") }
        parts.append(Self.spokenAge(age))
        if isSelected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    static func spokenAge(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: "just now"
        case 60..<3600: String(localized: "\(Int(seconds / 60)) minutes ago")
        case 3600..<86_400: String(localized: "\(Int(seconds / 3600)) hours ago")
        default: String(localized: "\(Int(seconds / 86_400)) days ago")
        }
    }

    private var typeName: String {
        switch type {
        case .url: "link"
        case .color: "color"
        default: type.rawValue
        }
    }

    private static func list(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.joined() }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}

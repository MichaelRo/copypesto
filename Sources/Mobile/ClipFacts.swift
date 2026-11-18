// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// A clip's facts (`DetailFact`, decided in Core) in words, one per line of the detail view's Facts section.
enum ClipFacts {
    @MainActor
    static func facts(for item: ClipboardItem, collectionName: String?, isShown: Bool) -> [DetailFact] {
        let text = item.type == .image ? "" : item.displayPreviewText
        return DetailPopoverContent.facts(.init(
            type: item.type,
            secretKind: isShown ? nil : item.sensitivity?.badgeLabel,
            isRemote: item.isRemote,
            copiedAt: item.copiedAt,
            byteSize: item.byteSize,
            characterCount: item.textLength,
            shownText: text,
            wasCut: false,
            language: item.detectedLanguage,
            fileCount: item.type == .file ? FileClip.urls(from: text).count : 0,
            rgb: item.type == .color ? rgb(of: item.gridPreview) : nil,
            collectionName: collectionName,
            pixelWidth: item.pixelWidth,
            pixelHeight: item.pixelHeight,
            pasteCount: item.pasteCount
        ))
    }

    static func rgb(of text: String) -> DetailPopoverContent.RGB? {
        guard let color = ColorLiteralParser.firstColor(in: text) else { return nil }
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return .init(red: channel(color.red), green: channel(color.green), blue: channel(color.blue))
    }

    static func text(for fact: DetailFact, locale: Locale = .current) -> String {
        switch fact {
        case .fromPhone: String(localized: "From another device")
        case let .copied(date): date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
        case let .language(name): name
        case let .secretKind(kind): kind
        case let .collection(name): String(localized: "In \(name)")
        case let .pasteCount(count): String(localized: "Pasted \(count) times")
        default: measure(fact)
        }
    }

    private static func measure(_ fact: DetailFact) -> String {
        switch fact {
        case let .characters(count): String(localized: "\(count) characters")
        case let .charactersShown(_, total): String(localized: "\(total) characters")
        case let .lines(count): String(localized: "\(count) lines")
        case let .bytes(count): ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
        case let .dimensions(width, height): "\(width) × \(height) px"
        case let .files(count): String(localized: "\(count) files")
        case let .rgb(red, green, blue): String(localized: "RGB \(red), \(green), \(blue)")
        default: ""
        }
    }
}

// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// The words for `DetailFact`s: one line, joined with a middle dot.
enum DetailFactsText {
    static func line(_ facts: [DetailFact], now: Date = .now, calendar: Calendar = .current) -> String {
        facts.map { text(for: $0, now: now, calendar: calendar) }.joined(separator: " · ")
    }

    static func facts(
        for item: ClipboardItem, collectionName: String?, shownText: String, wasCut: Bool, isRevealed: Bool = false
    )
    -> [DetailFact] {
        DetailPopoverContent.facts(.init(
            type: item.type,
            secretKind: isRevealed ? nil : item.sensitivity?.badgeLabel,
            isRemote: item.isRemote,
            copiedAt: item.timestamp,
            byteSize: item.byteSize,
            characterCount: item.textLength,
            shownText: shownText,
            wasCut: wasCut,
            language: item.detectedLanguage,
            fileCount: item.type == .file ? FileClip.urls(from: item.displayPreviewText).count : 0,
            rgb: item.type == .color ? colorComponents(of: item) : nil,
            collectionName: collectionName,
            pixelWidth: item.pixelWidth,
            pixelHeight: item.pixelHeight,
            pasteCount: item.pasteCount
        ))
    }

    private static func colorComponents(of item: ClipboardItem) -> DetailPopoverContent.RGB? {
        guard let color = ColorStringDetector.detect(in: item.gridPreview),
              let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func channel(_ value: CGFloat) -> Int {
            Int((value * 255).rounded())
        }
        return .init(
            red: channel(rgb.redComponent),
            green: channel(rgb.greenComponent),
            blue: channel(rgb.blueComponent)
        )
    }

    static func text(for fact: DetailFact, now: Date, calendar: Calendar) -> String {
        switch fact {
        case .fromPhone: String(localized: "From iPhone")
        case let .copied(date): when(date, now: now, calendar: calendar)
        case let .language(name): name
        case let .secretKind(kind): kind
        case let .collection(name): String(localized: "In \(name)")
        case let .pasteCount(count): String(localized: "Pasted \(count) times")
        default: measureText(for: fact)
        }
    }

    private static func measureText(for fact: DetailFact) -> String {
        switch fact {
        case let .characters(count): String(localized: "\(count) characters")
        case let .charactersShown(shown, total):
            String(localized: "First \(shown.formatted()) of \(total.formatted()) characters")
        case let .lines(count): String(localized: "\(count) lines")
        case let .bytes(count): ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
        case let .dimensions(width, height): "\(width) × \(height) px"
        case let .files(count): String(localized: "\(count) files")
        case let .rgb(red, green, blue): String(localized: "RGB \(red), \(green), \(blue)")
        default: ""
        }
    }

    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today, \(time)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return String(localized: "Yesterday, \(time)") }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        let day = sameYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.year().month(.abbreviated).day())
        return "\(day), \(time)"
    }
}

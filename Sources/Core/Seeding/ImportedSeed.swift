// SPDX-License-Identifier: MIT
import Foundation

/// A history shaped like one brought over from Paste, for measuring the shelf: about 1,100 clips spread over years
/// (the oldest in 2018), most of the old ones inside collections, links whose previews were never fetched, pictures
/// beyond the thumbnail cache's reach, GIFs, files that are gone, and sources that are not installed. It goes through
/// `PasteMigrator` like a real import. Deterministic, and only ever seeded in UI-test mode.
enum ImportedSeed {
    static let count = 1100
    static let pictureCount = 60
    static let collectionNames = [
        "Work", "Recipes", "Links", "Snippets", "Design", "Travel", "Receipts", "Ideas", "Code", "Home",
        "Reading", "Shopping", "Team", "Notes", "Misc"
    ]

    private static let installedSources = [
        "com.apple.Safari", "com.apple.Notes", "com.apple.mail", "com.apple.TextEdit", "com.apple.dt.Xcode",
        "com.apple.Terminal", "com.apple.MobileSMS", "com.apple.finder", "com.apple.Preview", "com.apple.iCal"
    ]
    private static let goneSources = (0..<15).map { "com.example.retired-app-\($0)" }
    private static let words = [
        "basil", "invoice", "meeting", "friday", "draft", "review", "release", "address", "quote", "reminder",
        "follow", "up", "contract", "budget", "ticket", "flight", "hotel", "recipe", "idea", "design"
    ]

    static func records(now: Date = .now) -> [PasteImportRecord] {
        let years: TimeInterval = 8 * 365 * 86_400
        return (0..<count).map { index in
            let age = years * Double(count - 1 - index) / Double(count - 1) + Double(index % 7) * 60
            let inCollection = index < count * 6 / 10 && index % 5 != 4
            return record(
                at: index, timestamp: now.addingTimeInterval(-age),
                pinboard: inCollection ? collectionNames[(index / 3) % collectionNames.count] : nil
            )
        }
    }

    private static func source(at index: Int) -> String {
        index % 4 == 0 ? goneSources[index % goneSources.count] : installedSources[index % installedSources.count]
    }

    private static func record(at index: Int, timestamp: Date, pinboard: String?) -> PasteImportRecord {
        let kind = kind(at: index)
        let representation: PasteImportRecord.Representation = switch kind {
        case .picture:
            .init(
                uti: "public.png",
                dataBase64: MixedSeed.pngData(seed: index, width: 900, height: 560).base64EncodedString()
            )
        case .gif:
            .init(uti: "com.compuserve.gif", dataBase64: SeedFixtures.animatedGIFData(side: 200).base64EncodedString())
        case .file:
            .init(uti: "public.file-url", dataBase64: Data(fileText(at: index).utf8).base64EncodedString())
        case .link:
            text("https://example.com/articles/\(index)/read-more?ref=import")
        case .code:
            text("func total\(index)(_ values: [Int]) -> Int {\n    values.reduce(0, +) * \(index % 9 + 1)\n}")
        case .color:
            text(String(format: "#%06X", (index * 2_654_435) & 0xFFFFFF))
        case .text:
            text(sentence(at: index))
        }
        return PasteImportRecord(
            pinboard: pinboard, title: index % 23 == 0 ? "Saved \(index)" : nil, timestamp: timestamp,
            sourceBundleID: source(at: index), representations: [representation]
        )
    }

    private enum Kind { case text, link, code, color, picture, gif, file }

    private static func kind(at index: Int) -> Kind {
        if index % 18 == 1, index / 18 < pictureCount { return .picture }
        switch index % 10 {
        case 3, 7: return .link
        case 5: return .code
        case 8: return .color
        case 9 where index % 50 == 9: return .gif
        case 9 where index % 25 == 4: return .file
        default: return .text
        }
    }

    private static func text(_ string: String) -> PasteImportRecord.Representation {
        .init(uti: "public.utf8-plain-text", dataBase64: Data(string.utf8).base64EncodedString())
    }

    private static func fileText(at index: Int) -> String {
        FileClip.encode([URL(fileURLWithPath: "/Volumes/OldMac/Documents/report-\(index).pdf")])
    }

    private static func sentence(at index: Int) -> String {
        let length = 4 + (index * 7) % 60
        let body = (0..<length).map { words[($0 * 5 + index) % words.count] }.joined(separator: " ")
        return "Clip \(index): \(body)."
    }
}

public extension SeedFixtures {
    static func importedRecords(now: Date = .now) -> [PasteImportRecord] {
        ImportedSeed.records(now: now)
    }
}

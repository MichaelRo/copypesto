// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The words around exporting and importing a collection file, with the plural forms in the String Catalog.
enum CollectionTransferText {
    static func exported(_ count: Int) -> String {
        String(localized: "Exported \(count) clips")
    }

    static func importQuestion(name: String) -> String {
        String(localized: "Import \u{201C}\(name)\u{201D}?")
    }

    static func importDetail(_ preview: CollectionImportPreview) -> String {
        var lines = [String(
            localized: "This file holds \(preview.importableCount) clips. They are added to your history."
        )]
        if preview.wouldRemove > 0 {
            lines.append(String(
                localized: "Up to \(preview.wouldRemove) of your oldest clips will be removed to fit your limit."
            ))
        }
        return lines.joined(separator: "\n")
    }

    static func imported(_ result: CollectionImportResult) -> String {
        guard result.itemsImported > 0 else { return String(localized: "Nothing new to import") }
        return String(localized: "Imported \(result.itemsImported) clips")
    }

    static func importDetail(_ result: CollectionImportResult) -> String {
        var lines: [String] = []
        let name = result.collectionName
        if result.itemsImported > 0 || result.addedToCollection > 0 {
            lines.append(String(localized: "Added to \u{201C}\(name)\u{201D}."))
        }
        if result.alreadyPresent > 0 { lines.append(CountText.alreadyHere(result.alreadyPresent)) }
        if result.addedToCollection > 0 {
            lines.append(String(localized: "\(result.addedToCollection) of them were put into the collection."))
        }
        lines.append(skippedLines(
            tooLarge: result.skippedTooLarge, sensitive: result.skippedSensitive, unreadable: result.skippedUnreadable,
            files: result.skippedFiles
        ))
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func skippedLines(tooLarge: Int, sensitive: Int, unreadable: Int, files: Int, overLimit: Int = 0) -> String {
        var lines: [String] = []
        if tooLarge > 0 { lines.append(String(localized: "\(tooLarge) were too large and were left out.")) }
        if sensitive > 0 { lines.append(String(localized: "\(sensitive) were left out: a secret or a private app.")) }
        if files > 0 { lines.append(String(localized: "\(files) were files, which are not shared.")) }
        if overLimit > 0 {
            lines.append(String(localized: "\(overLimit) were left out: a file holds at most 1,000 clips."))
        }
        if unreadable > 0 { lines.append(String(localized: "\(unreadable) could not be read and were left out.")) }
        return lines.joined(separator: "\n")
    }

    static func unreadable(_ error: any Error) -> String {
        switch error as? HistoryExporter.ImportError {
        case .tooManyRecords: String(
                localized: "That file holds more than 1,000 clips, which is more than Pesto imports."
            )
        case .fileTooLarge: String(localized: "That file is too large to be a collection.")
        case .unsupportedVersion: String(localized: "That file was made by a newer version of Pesto.")
        default: String(localized: "That file is not a Pesto collection.")
        }
    }
}

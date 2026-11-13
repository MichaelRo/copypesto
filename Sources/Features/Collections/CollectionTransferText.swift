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

    static func importDetail(clipCount: Int) -> String {
        String(localized: "This file holds \(clipCount) clips. They are added to your history and to the collection.")
    }

    static func imported(_ result: CollectionImportResult) -> String {
        guard result.itemsImported > 0 else { return String(localized: "Nothing new to import") }
        return String(localized: "Imported \(result.itemsImported) clips")
    }

    static func importDetail(_ result: CollectionImportResult, name: String) -> String {
        var lines: [String] = []
        if result.itemsImported > 0 { lines.append(String(localized: "Added to \u{201C}\(name)\u{201D}.")) }
        if result.alreadyPresent > 0 { lines.append(CountText.alreadyHere(result.alreadyPresent)) }
        lines.append(skippedLines(
            tooLarge: result.skippedTooLarge, sensitive: result.skippedSensitive, unreadable: result.skippedUnreadable,
            files: result.skippedFiles
        ))
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func skippedLines(tooLarge: Int, sensitive: Int, unreadable: Int, files: Int) -> String {
        var lines: [String] = []
        if tooLarge > 0 { lines.append(String(localized: "\(tooLarge) were too large and were left out.")) }
        if sensitive > 0 { lines.append(String(localized: "\(sensitive) were left out: a secret or a private app.")) }
        if files > 0 { lines.append(String(localized: "\(files) were files, which are not shared.")) }
        if unreadable > 0 { lines.append(String(localized: "\(unreadable) could not be read and were left out.")) }
        return lines.joined(separator: "\n")
    }
}

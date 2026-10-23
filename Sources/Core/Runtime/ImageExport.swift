// SPDX-License-Identifier: MIT
import Foundation
import UniformTypeIdentifiers

/// Where and under what name an image clip is saved by Save Image (⌘S).
public enum ImageExport {
    private static let longestName = 60

    /// ⌘S saves the focused clip only when it is a picture nothing covers. A picture the person has already shown
    /// despite the content filter is saved from its own menu, which knows that.
    public static func keyboardSaveAllowed(
        isImage: Bool, isFilteredContent: Bool, isHidden: Bool, isPendingAnalysis: Bool, isCoveredForSharing: Bool
    )
    -> Bool {
        isImage && !isFilteredContent && !isHidden && !isPendingAnalysis && !isCoveredForSharing
    }

    public static func fileExtension(forUTI identifier: String) -> String {
        UTType(identifier)?.preferredFilenameExtension ?? "png"
    }

    public static func baseName(title: String?, date: Date) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let cleaned = (title ?? "").components(separatedBy: forbidden).joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Pesto picture \(stamp(date))" }
        return String(cleaned.prefix(longestName))
    }

    /// The first free `base.ext`, `base 2.ext`, `base 3.ext`, so a save never replaces a file.
    public static func destination(
        in folder: URL, base: String, fileExtension: String, exists: (URL) -> Bool
    )
    -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var number = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) \(number)").appendingPathExtension(fileExtension)
            number += 1
        }
        return candidate
    }

    /// The folder Save Image writes to: the one chosen in Settings while it is a folder that exists, otherwise
    /// Downloads.
    /// `usedFallback` is true when a folder was chosen but is gone, so the person is told where the picture went.
    public static func saveFolder(
        chosenPath: String, downloads: URL, isUsableFolder: (URL) -> Bool
    )
    -> (folder: URL, usedFallback: Bool) {
        guard !chosenPath.isEmpty else { return (downloads, false) }
        let chosen = URL(fileURLWithPath: chosenPath, isDirectory: true)
        return isUsableFolder(chosen) ? (chosen, false) : (downloads, true)
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }
}

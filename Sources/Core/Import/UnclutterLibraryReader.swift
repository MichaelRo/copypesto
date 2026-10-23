// SPDX-License-Identifier: MIT
import AppKit
import Foundation

/// Unclutter stores clippings as files referenced by `history.plist` and `favorites.plist`.
public enum UnclutterLibraryReader {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Containers/com.softwareambience.Unclutter/Data/Library/Application Support"
            )
            .appendingPathComponent("Unclutter/Clipboard/history.plist")
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw Reader.ReadError.notFound
        }
        let historyURL = isDir.boolValue ? url.appendingPathComponent("history.plist") : url
        guard fileManager.fileExists(atPath: historyURL.path) else {
            throw Reader.ReadError.notRecognized
        }
        guard let size = (try? fileManager.attributesOfItem(atPath: historyURL.path))?[.size] as? Int,
              size <= Reader.maxDatabaseBytes else
        {
            throw Reader.ReadError.tooLarge
        }
        guard let data = try? Data(contentsOf: historyURL),
              let historyDict = (try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              )) as? [String: Any] else
        {
            throw Reader.ReadError.notRecognized
        }

        let baseDir = historyURL.deletingLastPathComponent()
        let favURL = baseDir.appendingPathComponent("favorites.plist")
        let altFavURL = baseDir.deletingLastPathComponent().appendingPathComponent(
            "Clipboard Favorites/favorites.plist"
        )
        let favDict: [String: Any]? = {
            for candidateURL in [favURL, altFavURL] {
                if let candidateData = try? Data(contentsOf: candidateURL),
                   let dict = (try? PropertyListSerialization.propertyList(
                       from: candidateData, options: [], format: nil
                   )) as? [String: Any]
                {
                    return dict
                }
            }
            return nil
        }()

        var records: [PasteImportRecord] = []
        var skipped = 0
        if let favDict {
            processEntries(favDict, baseDir: baseDir, isPinned: true, records: &records, skipped: &skipped)
        }
        processEntries(historyDict, baseDir: baseDir, isPinned: false, records: &records, skipped: &skipped)
        return ClipboardAppLibrary(records: records, skipped: skipped)
    }

    private static func processEntries(
        _ dict: [String: Any],
        baseDir: URL,
        isPinned: Bool,
        records: inout [PasteImportRecord],
        skipped: inout Int
    ) {
        typealias Reader = ClipboardAppLibraryReader
        let sortedKeys = dict.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        for key in sortedKeys {
            guard records.count < Reader.maxRecords else { return }
            guard let entry = dict[key] as? [String: Any],
                  let contentPath = entry["content"] as? String else
            {
                skipped += 1
                continue
            }
            let resolvedURL = contentPath.hasPrefix("/")
                ? URL(fileURLWithPath: contentPath)
                : baseDir.appendingPathComponent(contentPath)
            guard let fileData = try? Data(contentsOf: resolvedURL), !fileData.isEmpty,
                  fileData.count <= Reader.maxValueBytes else
            {
                skipped += 1
                continue
            }
            let type = (entry["type"] as? Int) ?? 0
            let reps: [PasteImportRecord.Representation]
            if type == 3 || resolvedURL.pathExtension.lowercased() == "png" {
                reps = [.init(uti: "public.png", dataBase64: fileData.base64EncodedString())]
            } else if let text = extractText(from: fileData), !text.isEmpty {
                reps = [.init(uti: "public.utf8-plain-text", dataBase64: Data(text.utf8).base64EncodedString())]
            } else {
                skipped += 1
                continue
            }
            let date = (entry["timestamp"] as? Date) ?? .now
            let bundleID = entry["sourceAppBundleId"] as? String
            records.append(PasteImportRecord(
                pinboard: isPinned ? "Favorites in Unclutter" : nil,
                title: nil,
                timestamp: date,
                sourceBundleID: bundleID,
                representations: reps
            ))
        }
    }

    private static func extractText(from data: Data) -> String? {
        if Thread.isMainThread {
            (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data))?.string
                ?? String(data: data, encoding: .utf8)
        } else {
            DispatchQueue.main.sync {
                (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data))?.string
                    ?? String(data: data, encoding: .utf8)
            }
        }
    }
}

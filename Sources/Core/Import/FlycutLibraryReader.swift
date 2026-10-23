// SPDX-License-Identifier: MIT
import Foundation

/// Flycut stores clippings in a preference plist file (`com.generalarcade.flycut.plist`).
public enum FlycutLibraryReader {
    public static var defaultDatabaseURL: URL {
        let container = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.generalarcade.flycut/Data/Library/Preferences/com.generalarcade.flycut.plist"
        )
        if FileManager.default.fileExists(atPath: container.path) { return container }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Preferences/com.generalarcade.flycut.plist"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        guard FileManager.default.fileExists(atPath: url.path) else { throw Reader.ReadError.notFound }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int else {
            throw Reader.ReadError.unreadable
        }
        guard size <= Reader.maxDatabaseBytes else { throw Reader.ReadError.tooLarge }
        guard let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              )) as? [String: Any],
              let store = plist["store"] as? [String: Any] else
        {
            throw Reader.ReadError.notRecognized
        }
        var records: [PasteImportRecord] = []
        var skipped = 0

        if let favs = store["favoritesList"] as? [[String: Any]] {
            processList(favs, pinned: true, records: &records, skipped: &skipped)
        }
        if let jcList = store["jcList"] as? [[String: Any]] {
            processList(jcList, pinned: false, records: &records, skipped: &skipped)
        }

        return ClipboardAppLibrary(records: records, skipped: skipped)
    }

    private static func processList(
        _ list: [[String: Any]],
        pinned: Bool,
        records: inout [PasteImportRecord],
        skipped: inout Int
    ) {
        typealias Reader = ClipboardAppLibraryReader
        for entry in list {
            guard records.count < Reader.maxRecords else { return }
            guard let contents = entry["Contents"] as? String, !contents.isEmpty else {
                skipped += 1
                continue
            }
            let time = (entry["Timestamp"] as? Double) ?? ((entry["Timestamp"] as? Int).map(Double.init) ?? 0)
            let date = time > 1_000_000_000
                ? Date(timeIntervalSince1970: time)
                : (time > 0 ? Date(timeIntervalSinceReferenceDate: time) : .now)
            let bundleID: String? = (entry["AppBundleURL"] as? String).flatMap {
                Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier
            }
            records.append(PasteImportRecord(
                pinboard: pinned ? "Favorites in Flycut" : nil,
                title: nil,
                timestamp: date,
                sourceBundleID: bundleID,
                representations: [.init(
                    uti: "public.utf8-plain-text",
                    dataBase64: Data(contents.utf8).base64EncodedString()
                )]
            ))
        }
    }
}

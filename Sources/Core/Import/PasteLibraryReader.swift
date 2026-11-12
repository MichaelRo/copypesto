// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// Finds Paste's local Core Data mirror (`Paste.db`) and opens a copy of it as a `PasteLibrarySnapshot`. It works on a
/// copy, so a running Paste is never disturbed and the original is never opened for writing; it never writes anywhere
/// but a temporary folder the snapshot removes. See `decisions/0011-read-only-surfaces.md` and
/// `decisions/0032-paste-import-keeps-pinboards-and-newest.md`.
public enum PasteLibraryReader {
    public enum ReadError: Error, Equatable {
        case notFound
        case notAPasteLibrary
        case unreadable
        case notEnoughSpace
    }

    public static let maxRecordBytes = 50_000_000

    public static var defaultLocation: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.wiheads.paste", isDirectory: true)
    }

    public static var defaultDatabaseURL: URL {
        defaultLocation.appendingPathComponent("Paste.db")
    }

    public static func candidateDatabaseURLs(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    )
    -> [URL] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent("Application Support/com.wiheads.paste/Paste.db"),
            library.appendingPathComponent("Group Containers/group.com.wiheads.paste/Paste.db"),
            library.appendingPathComponent(
                "Containers/com.wiheads.paste/Data/Library/Application Support/Paste/Paste.db"
            ),
            library.appendingPathComponent(
                "Containers/com.wiheads.paste-setapp/Data/Library/Application Support/Paste/Paste.db"
            ),
            library.appendingPathComponent("Application Support/com.wiheads.paste-setapp/Paste.db")
        ]
    }

    public static func existingDatabaseURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    )
    -> URL? {
        candidateDatabaseURLs(homeDirectory: homeDirectory).first { fileManager.fileExists(atPath: $0.path) }
    }

    struct JoinTable {
        let table: String
        let snippets: String
        let lists: String
    }

    /// Core Data names a many-to-many join table after the order of its entities (`Z_6LISTS`, columns `Z_6SNIPPETS` and
    /// `Z_13LISTS` in the version this was written against), and the numbers change when Paste's model does. The table
    /// is found by what its two columns end in.
    static func joinTable(in db: OpaquePointer) -> JoinTable? {
        var statement: OpaquePointer?
        let tables = "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'Z\\_%' ESCAPE '\\'"
        guard sqlite3_prepare_v2(db, tables, -1, &statement, nil) == SQLITE_OK, let rows = statement else { return nil }
        var names: [String] = []
        while sqlite3_step(rows) == SQLITE_ROW {
            names.append(text(rows, 0) ?? "")
        }
        sqlite3_finalize(rows)
        for name in names.sorted() where name.hasSuffix("LISTS") {
            let columns = columnNames(of: name, in: db)
            let snippets = columns.first { $0.range(of: #"^Z_\d+SNIPPETS$"#, options: .regularExpression) != nil }
            let lists = columns.first { $0.range(of: #"^Z_\d+LISTS$"#, options: .regularExpression) != nil }
            if let snippets, let lists, columns.count == 2 { return JoinTable(
                table: name,
                snippets: snippets,
                lists: lists
            ) }
        }
        return nil
    }

    static func columnNames(of table: String, in db: OpaquePointer) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(table)\")", -1, &statement, nil) == SQLITE_OK,
              let rows = statement else { return [] }
        defer { sqlite3_finalize(rows) }
        var names: [String] = []
        while sqlite3_step(rows) == SQLITE_ROW {
            names.append(text(rows, 1) ?? "")
        }
        return names
    }

    static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

/// Core Data keeps a binary value that "Allows External Storage" either in its column (marker byte 0x01, then the
/// bytes) or, when it is large, in a file beside the store: the column then holds marker 0x02, the file's name (a UUID)
/// and a NUL, and the bytes, without a marker, are in `.<store name>_SUPPORT/_EXTERNAL_DATA/<name>`. Checked against a
/// store Core Data wrote; Apple does not document it. Pictures and files in Paste are the values that go external.
enum PasteExternalPayload {
    static let externalMarker: UInt8 = 0x02

    static func folder(besideDatabaseAt url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent)_SUPPORT", isDirectory: true)
            .appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
    }

    /// The file name in a column value, only when the value is an external reference holding a plain UUID: a name
    /// with a slash or `..` in it never reaches the file system.
    static func fileName(in blob: Data) -> String? {
        guard blob.first == externalMarker, blob.count < 64 else { return nil }
        guard let name = String(bytes: blob.dropFirst().prefix { $0 != 0 }, encoding: .utf8) else { return nil }
        return name.range(
            of: #"^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$"#, options: .regularExpression
        ) == nil ? nil : name
    }

    enum Outcome: Equatable {
        case bytes(Int)
        case unusable
    }

    /// Opens without following a link and reads the size of the open file, so what is measured is what is read.
    private static func open(_ name: String?, in folder: URL?) -> (descriptor: Int32, size: Int)? {
        guard let name, let folder else { return nil }
        let descriptor = Darwin.open(folder.appendingPathComponent(name).path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            return nil
        }
        return (descriptor, Int(info.st_size))
    }

    static func size(of name: String?, in folder: URL?) -> Outcome {
        guard let file = open(name, in: folder) else { return .unusable }
        close(file.descriptor)
        return .bytes(file.size)
    }

    /// The file's bytes, or nil when it is missing, not a plain file, or over `limit` (nothing is read then).
    static func read(_ name: String?, in folder: URL?, limit: Int) -> Data? {
        guard let file = open(name, in: folder), file.size <= limit else { return nil }
        return try? FileHandle(fileDescriptor: file.descriptor, closeOnDealloc: true).readToEnd() ?? Data()
    }
}

/// `ZPASTEBOARDITEMS` is one marker byte followed by an `NSKeyedArchiver` archive of `[PasteCore.PasteboardItem]`;
/// each item holds `types` (UTIs in order) and `data` (UTI → bytes). A stand-in class answers to Paste's class name,
/// so nothing of Paste's is needed and secure decoding allows only plain Foundation containers.
enum PasteArchiveDecoder {
    @objc(PestoDecodedPasteItem)
    private final class Item: NSObject, NSSecureCoding {
        static var supportsSecureCoding: Bool {
            true
        }

        let types: [String]
        let data: [String: Data]

        required init?(coder: NSCoder) {
            types = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "types") as? [String] ?? []
            data = coder.decodeObject(of: [NSDictionary.self, NSString.self, NSData.self], forKey: "data")
                as? [String: Data] ?? [:]
        }

        func encode(with _: NSCoder) {}
    }

    /// A column value: the inline marker byte, then the archive.
    static func representations(in blob: Data) -> [PasteImportRecord.Representation]? {
        blob.count > 1 ? representations(inArchive: blob.dropFirst()) : nil
    }

    static func representations(inArchive archive: Data) -> [PasteImportRecord.Representation]? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archive) else { return nil }
        unarchiver.requiresSecureCoding = true
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        unarchiver.setClass(Item.self, forClassName: "PasteCore.PasteboardItem")
        defer { unarchiver.finishDecoding() }
        guard let items = unarchiver.decodeObject(of: [NSArray.self, Item.self], forKey: NSKeyedArchiveRootObjectKey)
            as? [Item], let first = items.first else { return nil }
        let ordered = first.types.filter { first.data[$0] != nil }
        let representations = ordered.compactMap { uti in
            first.data[uti].map { PasteImportRecord.Representation(uti: uti, dataBase64: $0.base64EncodedString()) }
        }
        return representations.isEmpty ? nil : representations
    }
}

// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// One sealed file in the app group that the iOS app writes, whole and atomically, and an extension only reads (ADR
/// 0051, ADR 0052). It never holds plaintext, and a read takes at most the format's bound.
public struct SealedGroupFile: Sendable {
    public let root: URL
    public let format: SealedFileFormat

    public init(root: URL, format: SealedFileFormat) {
        self.root = root
        self.format = format
    }

    /// The app group's file, or nil when the group is not available to this build.
    public static func current(_ format: SealedFileFormat) -> SealedGroupFile? {
        AppPaths.sharedGroupDirectory.map { SealedGroupFile(root: $0, format: format) }
    }

    public var url: URL {
        root.appendingPathComponent(format.fileName)
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }

    public func write(_ value: some Encodable, with key: SymmetricKey) throws {
        let sealed = try SealedFileEnvelope.seal(value, as: format, with: key)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try sealed.write(to: url, options: Self.writeOptions)
    }

    public func read<Value: Decodable>(_ type: Value.Type, with key: SymmetricKey) throws -> Value {
        guard exists else { throw SealedFileError.missing }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: format.maxFileBytes + 1) ?? Data()
        guard data.count <= format.maxFileBytes else { throw SealedFileError.tooLarge }
        return try SealedFileEnvelope.open(type, from: data, as: format, with: key)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

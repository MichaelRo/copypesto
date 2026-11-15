// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The one quick-insert file in the app group (ADR 0051). Only the app writes it, whole and atomically; the AutoFill
/// extension only reads it. It never holds plaintext.
public struct QuickInsertFile: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The app group's file, or nil when the group is not available to this build.
    public static var current: QuickInsertFile? {
        AppPaths.sharedGroupDirectory.map(QuickInsertFile.init(root:))
    }

    public var url: URL {
        root.appendingPathComponent(AppIdentity.quickInsertFileName)
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

    public func write(_ set: QuickInsertSet, with key: SymmetricKey) throws {
        let sealed = try QuickInsertEnvelope.seal(set, with: key)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try sealed.write(to: url, options: Self.writeOptions)
    }

    public func read(with key: SymmetricKey) throws -> QuickInsertSet {
        guard exists else { throw QuickInsertError.missing }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: QuickInsertPolicy.maxFileBytes + 1) ?? Data()
        guard data.count <= QuickInsertPolicy.maxFileBytes else { throw QuickInsertError.tooLarge }
        return try QuickInsertEnvelope.open(data, with: key)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

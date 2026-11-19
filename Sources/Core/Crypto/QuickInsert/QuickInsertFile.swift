// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The one quick-insert file in the app group (ADRs 0051, 0061). Only the app writes it; AutoFill and the keyboard only
/// read it.
public struct QuickInsertFile: Sendable {
    private let file: SealedGroupFile

    public init(root: URL) {
        file = SealedGroupFile(root: root, format: .quickInsert)
    }

    /// The app group's file, or nil when the group is not available to this build.
    public static var current: QuickInsertFile? {
        AppPaths.sharedGroupDirectory.map(QuickInsertFile.init(root:))
    }

    public var root: URL {
        file.root
    }

    public var url: URL {
        file.url
    }

    public var exists: Bool {
        file.exists
    }

    /// When the app last wrote the file, so a reader that stays running opens it again only after a change; nil when
    /// there is no file.
    public var modificationDate: Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    public func write(_ set: QuickInsertSet, with key: SymmetricKey) throws {
        try file.write(set, with: key)
    }

    public func read(with key: SymmetricKey) throws -> QuickInsertSet {
        try file.read(QuickInsertSet.self, with: key)
    }

    /// How AutoFill and the keyboard read the set: nil when there is nothing to open yet (no key, or no file),
    /// otherwise the set; a set that will not open throws, so the caller can log why.
    public func openSet(keys: QuickInsertKeyStore) throws -> QuickInsertSet? {
        guard let key = try keys.key() else { return nil }
        do {
            return try read(with: key)
        } catch QuickInsertError.missing {
            return nil
        }
    }

    public func remove() {
        file.remove()
    }
}

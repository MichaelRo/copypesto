// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The one quick-insert file in the app group (ADR 0051). Only the app writes it; the AutoFill extension only reads it.
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

    public func write(_ set: QuickInsertSet, with key: SymmetricKey) throws {
        try file.write(set, with: key)
    }

    public func read(with key: SymmetricKey) throws -> QuickInsertSet {
        try file.read(QuickInsertSet.self, with: key)
    }

    public func remove() {
        file.remove()
    }
}

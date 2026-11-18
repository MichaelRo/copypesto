// SPDX-License-Identifier: MIT
import Foundation

/// The app group's inbox (ADR 0047): the public key the app publishes, and one sealed file per shared item. The share
/// extension only seals and deposits; the app reads, opens and removes. Nothing here ever holds plaintext on disk.
public struct SharedInbox: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The app group's inbox, or nil when the group is not available to this build.
    public static var current: SharedInbox? {
        AppPaths.sharedGroupDirectory.map(SharedInbox.init(root:))
    }

    public var directory: URL {
        root.appendingPathComponent(AppIdentity.inboxDirectoryName, isDirectory: true)
    }

    public var publicKeyURL: URL {
        root.appendingPathComponent(AppIdentity.inboxPublicKeyFileName)
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }

    public func publishedKey() throws -> InboxPublicKey? {
        guard FileManager.default.fileExists(atPath: publicKeyURL.path) else { return nil }
        return try InboxPublicKey.parse(Self.read(publicKeyURL, limit: 256))
    }

    /// Writes the key unless the same one is already there; a missing, damaged or different file is replaced.
    public func publish(_ key: InboxPublicKey) throws {
        if (try? publishedKey()) == key { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try key.serialized().write(to: publicKeyURL, options: Self.writeOptions)
    }

    /// Seals `item` to the published key and writes it as one new file. Refuses before writing anything when there
    /// is no key, the inbox is full, or the item is over its limit.
    @discardableResult
    public func deposit(_ item: InboxItem) throws -> URL {
        let item = try item.validated()
        guard let key = try? publishedKey() else { throw InboxError.noKey }
        let pending = pendingFiles()
        let pendingBytes = pending.reduce(0) { $0 + Self.size(of: $1) }
        guard pending.count < InboxPolicy.maxPendingFiles,
              pendingBytes + item.payload.count <= InboxPolicy.maxPendingBytes else { throw InboxError.full }
        let sealed = try InboxEnvelope.seal(item, to: key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(AppIdentity.inboxFileExtension)
        try sealed.write(to: url, options: Self.writeOptions)
        return url
    }

    /// The sealed files waiting, oldest first.
    public func pendingFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        )) ?? []
        return files.filter { $0.pathExtension == AppIdentity.inboxFileExtension }
            .sorted { Self.created($0) < Self.created($1) }
    }

    /// Everything in the inbox folder that is not a sealed file (an interrupted write's leftovers).
    public func strayFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension != AppIdentity.inboxFileExtension }
    }

    /// A file's bytes, or `tooLarge` without reading more than the limit allows.
    public func contents(of url: URL) throws -> Data {
        try Self.read(url, limit: InboxPolicy.maxFileBytes)
    }

    public func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    public static func created(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func read(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw InboxError.tooLarge }
        return data
    }
}

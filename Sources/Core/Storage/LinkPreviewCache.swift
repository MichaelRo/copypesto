// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

public final class LinkPreviewCache: @unchecked Sendable {
    public static let shared = LinkPreviewCache()

    public struct Entry: Codable, Sendable {
        public let title: String?
        public let siteName: String?
        public let faviconData: Data?
        public let ogImageData: Data?
        public let fetchedAt: Date
        public let isNegative: Bool

        public init(
            title: String?,
            siteName: String?,
            faviconData: Data?,
            ogImageData: Data?,
            fetchedAt: Date = .now,
            isNegative: Bool = false
        ) {
            self.title = title
            self.siteName = siteName
            self.faviconData = faviconData
            self.ogImageData = ogImageData
            self.fetchedAt = fetchedAt
            self.isNegative = isNegative
        }
    }

    private let file: SealedFile
    private let hashKey: SymmetricKey?
    private let ttl: TimeInterval
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    /// The titles and pictures of pages the person copied links to are sealed on disk like the rest of the store
    /// (`SealedFile`), and keyed by a keyed hash of the address, so neither can be read or tested without the key.
    public init(
        fileURL: URL = AppPaths.supportDirectory
            .appendingPathComponent("link-previews", isDirectory: true)
            .appendingPathComponent("metadata-cache.sealed"),
        ttl: TimeInterval = 14 * 24 * 3600,
        encryption: BlobEncryption = BlobEncryption()
    ) {
        file = SealedFile(url: fileURL, encryption: encryption)
        hashKey = try? encryption.loadOrCreateKey()
        self.ttl = ttl
        Self.removePlaintextCacheOfOlderVersions(beside: fileURL)
        loadFromDisk()
    }

    public func entry(for url: URL, now: Date = .now) -> Entry? {
        lock.withLock {
            let cacheKey = key(for: url)
            guard let entry = entries[cacheKey] else { return nil }
            if now.timeIntervalSince(entry.fetchedAt) > ttl {
                entries[cacheKey] = nil
                persistToDisk()
                return nil
            }
            return entry
        }
    }

    public func store(_ entry: Entry, for url: URL) {
        lock.withLock {
            let cacheKey = key(for: url)
            entries[cacheKey] = entry
            if entries.count > 500 {
                let sorted = entries.sorted { $0.value.fetchedAt < $1.value.fetchedAt }
                for item in sorted.prefix(entries.count - 500) {
                    entries[item.key] = nil
                }
            }
            persistToDisk()
        }
    }

    public func remove(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        lock.withLock {
            urls.forEach { entries[key(for: $0)] = nil }
            persistToDisk()
        }
    }

    public func clear() {
        lock.withLock {
            entries.removeAll()
        }
        file.remove()
    }

    private func key(for url: URL) -> String {
        let canonical = url.absoluteString.lowercased()
        let plain = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return ContentHash.stored(plain, key: hashKey)
    }

    /// Before the cache was sealed it was `metadata-cache.json`, readable by anyone with the file.
    private static func removePlaintextCacheOfOlderVersions(beside sealed: URL) {
        let legacy = sealed.deletingLastPathComponent().appendingPathComponent("metadata-cache.json")
        guard legacy.standardizedFileURL != sealed.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: legacy)
    }

    private func loadFromDisk() {
        guard let data = file.read(),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        lock.withLock {
            self.entries = decoded
        }
    }

    private func persistToDisk() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? file.write(data)
    }
}

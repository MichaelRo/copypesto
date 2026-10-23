// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// Decrypted previews, so a search over thousands of items decrypts each once instead of on every keystroke.
/// Plaintext lives here, so it is cleared whenever the history locks or is cleared.
public final class PreviewTextCache: Sendable {
    private struct Key: Hashable {
        let id: UUID
        let nonce: Data
    }

    /// A dictionary that, when full, drops the entry that has been in it longest rather than all of them: a history at
    /// the 10,000-clip maximum fills a whole map, and emptying it made every card decrypt again as it drew.
    private struct Bounded<Value> {
        private var values: [Key: Value] = [:]
        private var order: [Key] = []
        private var oldest = 0

        var count: Int {
            values.count
        }

        subscript(key: Key) -> Value? {
            values[key]
        }

        mutating func insert(_ value: Value, for key: Key, capacity: Int) {
            if values[key] == nil {
                while values.count >= capacity, oldest < order.count {
                    values[order[oldest]] = nil
                    oldest += 1
                }
                order.append(key)
                if oldest > 1024, oldest * 2 > order.count {
                    order.removeFirst(oldest)
                    oldest = 0
                }
            }
            values[key] = value
        }

        var isEmpty: Bool {
            values.isEmpty
        }

        mutating func removeAll() {
            values.removeAll()
            order.removeAll()
            oldest = 0
        }
    }

    public static let shared = PreviewTextCache()

    private let capacity: Int
    private let entries = Mutex(Bounded<String>())
    private let foldedEntries = Mutex(Bounded<String>())
    private let metadataEntries = Mutex(Bounded<ItemMetadata>())
    private let embeddingEntries = Mutex(Bounded<Data>())

    public init(capacity: Int = 10_000) {
        self.capacity = capacity
    }

    public var count: Int {
        entries.withLock { $0.count }
    }

    var foldedCount: Int {
        foldedEntries.withLock { $0.count }
    }

    var embeddingCount: Int {
        embeddingEntries.withLock { $0.count }
    }

    public var isEmpty: Bool {
        entries.withLock { $0.isEmpty } && foldedEntries.withLock { $0.isEmpty } && metadataEntries
            .withLock { $0.isEmpty } && embeddingEntries.withLock { $0.isEmpty }
    }

    public func text(id: UUID, nonce: Data, decrypt: () -> String?) -> String? {
        let key = Key(id: id, nonce: nonce)
        if let hit = entries.withLock({ $0[key] }) { return hit }
        guard let text = decrypt() else { return nil }
        entries.withLock { $0.insert(text, for: key, capacity: capacity) }
        return text
    }

    /// The preview folded for search (case and diacritics), computed once per preview.
    public func folded(id: UUID, nonce: Data, decrypt: () -> String?) -> String? {
        let key = Key(id: id, nonce: nonce)
        if let hit = foldedEntries.withLock({ $0[key] }) { return hit }
        guard let text = text(id: id, nonce: nonce, decrypt: decrypt) else { return nil }
        let folded = SearchMatching.fold(text)
        foldedEntries.withLock { $0.insert(folded, for: key, capacity: capacity) }
        return folded
    }

    /// A clip's title, note and tags, opened once per ciphertext.
    public func metadata(id: UUID, nonce: Data, decrypt: () -> ItemMetadata?) -> ItemMetadata? {
        let key = Key(id: id, nonce: nonce)
        if let hit = metadataEntries.withLock({ $0[key] }) { return hit }
        guard let value = decrypt() else { return nil }
        metadataEntries.withLock { $0.insert(value, for: key, capacity: capacity) }
        return value
    }

    /// A clip's search vector, opened once per ciphertext so a search over thousands of clips does not decrypt them all
    /// again on every keystroke.
    public func embedding(id: UUID, nonce: Data, decrypt: () -> Data?) -> Data? {
        let key = Key(id: id, nonce: nonce)
        if let hit = embeddingEntries.withLock({ $0[key] }) { return hit }
        guard let value = decrypt() else { return nil }
        embeddingEntries.withLock { $0.insert(value, for: key, capacity: capacity) }
        return value
    }

    public func clear() {
        entries.withLock { $0.removeAll() }
        foldedEntries.withLock { $0.removeAll() }
        metadataEntries.withLock { $0.removeAll() }
        embeddingEntries.withLock { $0.removeAll() }
    }
}

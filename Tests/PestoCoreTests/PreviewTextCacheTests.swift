// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("PreviewTextCache")
struct PreviewTextCacheTests {
    private let id = UUID()
    private let nonce = Data(repeating: 1, count: 12)

    @Test("the decrypt closure runs once for repeated reads of the same preview")
    func whenReadTwice_thenDecryptedOnce() {
        let cache = PreviewTextCache()
        var calls = 0

        let first = cache.text(id: id, nonce: nonce) { calls += 1
            return "secret text"
        }
        let second = cache.text(id: id, nonce: nonce) { calls += 1
            return "secret text"
        }

        #expect(first == "secret text" && second == "secret text")
        #expect(calls == 1)
    }

    @Test("a new nonce means the preview was rewritten, so it is decrypted again")
    func whenNonceChanges_thenDecryptedAgain() {
        let cache = PreviewTextCache()

        _ = cache.text(id: id, nonce: nonce) { "old" }
        let updated = cache.text(id: id, nonce: Data(repeating: 2, count: 12)) { "new" }

        #expect(updated == "new")
    }

    @Test("a failed decryption is not cached")
    func whenDecryptFails_thenNotCached() {
        let cache = PreviewTextCache()

        let first = cache.text(id: id, nonce: nonce) { nil }
        let second = cache.text(id: id, nonce: nonce) { "recovered" }

        #expect(first == nil)
        #expect(second == "recovered")
    }

    @Test("clear forgets every plaintext")
    func whenCleared_thenDecryptedAgain() {
        let cache = PreviewTextCache()
        var calls = 0
        _ = cache.text(id: id, nonce: nonce) { calls += 1
            return "x"
        }

        cache.clear()
        _ = cache.text(id: id, nonce: nonce) { calls += 1
            return "x"
        }

        #expect(calls == 2)
    }

    @Test("the cache stays bounded")
    func whenOverCapacity_thenBounded() {
        let cache = PreviewTextCache(capacity: 10)

        for _ in 0..<50 {
            _ = cache.text(id: UUID(), nonce: nonce) { "t" }
        }

        #expect(cache.count <= 10)
    }

    @Test("the folded form is computed once and ignores case and diacritics")
    func foldedIsCachedAndFolded() {
        let cache = PreviewTextCache()
        var calls = 0

        let first = cache.folded(id: id, nonce: nonce) { calls += 1
            return "Café AU Lait"
        }
        let second = cache.folded(id: id, nonce: nonce) { calls += 1
            return "Café AU Lait"
        }

        #expect(first == "cafe au lait" && second == "cafe au lait")
        #expect(calls == 1)
    }

    @Test("a search vector is opened once per ciphertext, and clearing the cache drops it")
    func whenVectorReadTwice_thenDecryptedOnce_andClearForgetsIt() {
        let cache = PreviewTextCache()
        var calls = 0
        let vector = Data(repeating: 7, count: 3072)

        _ = cache.embedding(id: id, nonce: nonce) { calls += 1
            return vector
        }
        let again = cache.embedding(id: id, nonce: nonce) { calls += 1
            return vector
        }
        #expect(again == vector)
        #expect(calls == 1)
        #expect(!cache.isEmpty)

        cache.clear()
        #expect(cache.isEmpty)
    }
}

@Suite("PreviewTextCache eviction (P-04)")
struct PreviewTextCacheEvictionTests {
    private let nonce = Data(repeating: 1, count: 12)

    @Test("a full cache drops its oldest entry, not everything")
    func whenCapacityIsReached_thenOnlyTheOldestGoes() {
        let capacity = 100
        let cache = PreviewTextCache(capacity: capacity)
        let ids = (0...capacity).map { _ in UUID() }

        for (index, id) in ids.enumerated() {
            _ = cache.text(id: id, nonce: nonce) { "text \(index)" }
        }

        #expect(cache.count == capacity)
        var decryptions = 0
        for id in ids.dropFirst() {
            _ = cache.text(id: id, nonce: nonce) {
                decryptions += 1
                return "again"
            }
        }
        #expect(decryptions == 0, "\(decryptions) of the newest \(capacity) had to be decrypted again")
        _ = cache.text(id: ids[0], nonce: nonce) {
            decryptions += 1
            return "again"
        }
        #expect(decryptions == 1, "the oldest entry should have been the one evicted")
    }

    @Test("every kind of entry is bounded the same way")
    func whenEveryMapFills_thenNoneGrowsPastCapacity() {
        let cache = PreviewTextCache(capacity: 10)
        for _ in 0..<25 {
            let id = UUID()
            _ = cache.folded(id: id, nonce: nonce) { "Folded" }
            _ = cache.embedding(id: id, nonce: nonce) { Data([1]) }
        }
        #expect(cache.count <= 10)
        #expect(cache.foldedCount <= 10)
        #expect(cache.embeddingCount <= 10)
    }
}

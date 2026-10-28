// SPDX-License-Identifier: MIT
import Foundation

/// Finds clips whose text looks like another's, by banding their `TextSignature`s (locality-sensitive hashing): two
/// signatures that agree on every row of one band land in one bucket. In memory only; rebuilt from the sealed
/// signatures at launch.
public struct SimilarityIndex: Sendable {
    public struct Match: Equatable, Sendable {
        public let id: UUID
        public let similarity: Double
    }

    static let bands = 16
    static let rowsPerBand = TextSignature.width / bands

    private var signatures: [UUID: TextSignature] = [:]
    /// Per band, the bucket hash and the clip, packed (hash in the high 32 bits) and kept sorted for binary search.
    private var buckets: [[UInt64]] = Array(repeating: [], count: bands)
    private var slots: [UUID: UInt32] = [:]
    private var ids: [UUID?] = []

    public init() {}

    public var count: Int {
        signatures.count
    }

    /// An estimate of the memory the index holds, for the budget tests.
    public var approximateBytes: Int {
        signatures.count * (TextSignature.width * 4 + 48) + buckets.reduce(0) { $0 + $1.count * 8 } + ids.count * 17
    }

    public mutating func insert(_ signature: TextSignature, for id: UUID) {
        remove(id)
        let slot = UInt32(ids.count)
        ids.append(id)
        slots[id] = slot
        signatures[id] = signature
        for band in 0..<Self.bands {
            let key = Self.key(of: signature, band: band, slot: slot)
            let at = Self.insertionPoint(in: buckets[band], for: key)
            buckets[band].insert(key, at: at)
        }
    }

    public mutating func remove(_ id: UUID) {
        guard let slot = slots.removeValue(forKey: id), let signature = signatures.removeValue(forKey: id) else { return }
        for band in 0..<Self.bands {
            let key = Self.key(of: signature, band: band, slot: slot)
            let at = Self.insertionPoint(in: buckets[band], for: key)
            if at < buckets[band].count, buckets[band][at] == key { buckets[band].remove(at: at) }
        }
        ids[Int(slot)] = nil
    }

    public mutating func removeAll() {
        self = SimilarityIndex()
    }

    /// The clips at least `threshold` like `signature`, most alike first, never `excluding` itself.
    public func matches(for signature: TextSignature, threshold: Double = 0.5, excluding: UUID? = nil) -> [Match] {
        var seen = Set<UInt32>()
        var found: [Match] = []
        for band in 0..<Self.bands {
            let prefix = Self.hash(of: signature, band: band)
            var at = Self.insertionPoint(in: buckets[band], for: UInt64(prefix) << 32)
            while at < buckets[band].count, UInt32(buckets[band][at] >> 32) == prefix {
                let slot = UInt32(truncatingIfNeeded: buckets[band][at])
                at += 1
                guard seen.insert(slot).inserted, let id = ids[Int(slot)], id != excluding,
                      let other = signatures[id] else { continue }
                let similarity = signature.similarity(to: other)
                if similarity >= threshold { found.append(Match(id: id, similarity: similarity)) }
            }
        }
        return found.sorted { $0.similarity > $1.similarity }
    }

    private static func hash(of signature: TextSignature, band: Int) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for row in 0..<rowsPerBand {
            hash = (hash ^ signature.values[band * rowsPerBand + row]) &* 16_777_619
        }
        return hash
    }

    private static func key(of signature: TextSignature, band: Int, slot: UInt32) -> UInt64 {
        UInt64(hash(of: signature, band: band)) << 32 | UInt64(slot)
    }

    private static func insertionPoint(in sorted: [UInt64], for key: UInt64) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < key { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

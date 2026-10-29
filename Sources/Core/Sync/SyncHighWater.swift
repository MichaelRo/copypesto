// SPDX-License-Identifier: MIT
import Foundation

/// How far this Mac has applied every other Mac's log: the highest sequence and the hash of that segment's manifest.
/// It is what makes a rolled-back, forked or re-ordered folder visible, and it is kept sealed in this Mac's own store.
public struct SyncHighWater: Codable, Equatable, Sendable {
    public struct Mark: Codable, Equatable, Sendable {
        public var epoch: UInt32
        public var sequence: UInt64
        public var manifestHash: String
    }

    public enum Decision: Equatable, Sendable {
        case apply
        case duplicate
        /// An earlier segment is not here yet (still downloading); wait for it.
        case gap
    }

    public private(set) var marks: [String: Mark] = [:]

    public init() {}

    public func mark(for deviceID: String) -> Mark? {
        marks[deviceID]
    }

    /// Decides what to do with a segment's manifest (already authenticated and signed). Throws for anything that would
    /// take the log backwards or sideways.
    public func decide(_ manifest: SyncManifest, currentEpoch: UInt32) throws -> Decision {
        guard manifest.epoch == currentEpoch else { throw SyncError.wrongEpoch }
        // First contact with a device (or with its log in this epoch): the caller feeds its segments oldest first.
        guard let mark = marks[manifest.deviceID], mark.epoch == manifest.epoch else { return .apply }
        if manifest.lastSequence <= mark.sequence {
            if manifest.lastSequence == mark.sequence, try manifest.hash() != mark.manifestHash { throw SyncError.fork }
            return .duplicate
        }
        if manifest.firstSequence <= mark.sequence { throw SyncError.fork }
        if manifest.firstSequence > mark.sequence + 1 { return .gap }
        guard manifest.previousManifestHash == mark.manifestHash else { throw SyncError.brokenChain }
        return .apply
    }

    public mutating func record(_ manifest: SyncManifest) throws {
        marks[manifest.deviceID] = try Mark(
            epoch: manifest.epoch, sequence: manifest.lastSequence, manifestHash: manifest.hash()
        )
    }

    public mutating func forget(_ deviceID: String) {
        marks[deviceID] = nil
    }
}

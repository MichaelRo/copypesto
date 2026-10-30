// SPDX-License-Identifier: MIT
import Foundation

/// What Settings says about sync: always a real state, never "connected" by default.
public enum SyncStatus: Equatable, Sendable {
    case off
    case paused
    case upToDate(Date)
    case receiving(done: Int, total: Int)
    case waitingForFolder
    case folderMissing
    case nothingNew(since: Date)
    case needsKey
    case refused(String)
}

/// Where the marks of how far each other Mac's log has been applied are kept: sealed in this Mac's own store.
public protocol SyncHighWaterStoring: Sendable {
    func load() -> SyncHighWater
    func save(_ water: SyncHighWater)
}

public struct SealedHighWaterStore: SyncHighWaterStoring {
    private let file: SealedFile

    public init(url: URL) {
        file = SealedFile(url: url)
    }

    public func load() -> SyncHighWater {
        file.read().flatMap { try? JSONDecoder().decode(SyncHighWater.self, from: $0) } ?? SyncHighWater()
    }

    public func save(_ water: SyncHighWater) {
        guard let data = try? JSONEncoder().encode(water) else { return }
        try? file.write(data)
    }
}

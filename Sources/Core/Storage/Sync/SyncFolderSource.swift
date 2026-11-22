// SPDX-License-Identifier: MIT
import Foundation

/// Why the folder the person chose cannot be used right now. Each one is repaired by choosing the folder again.
public enum SyncFolderProblem: Equatable, Sendable {
    /// The system says the remembered link to the folder is out of date.
    case stale
    /// The remembered link no longer leads to a folder.
    case unresolvable
    /// The folder was found, but it cannot be opened or is gone.
    case unreachable
}

public enum SyncFolderResolution: Equatable, Sendable {
    case notChosen
    /// The sync folder itself (the one that holds the vault and `devices/`), open for as long as sync uses it.
    case ready(URL)
    case needsRepair(SyncFolderProblem)
}

/// Where a device's sync folder comes from and how access to it is held. `SyncController` is given only the URL; a
/// source keeps the folder open from `resolve` (or `choose`) until `relinquish`, in balance.
@MainActor
public protocol SyncFolderSource: AnyObject {
    var hasChosenFolder: Bool { get }
    func resolve() -> SyncFolderResolution
    func resolveAsync() async -> SyncFolderResolution
    /// Remembers the folder the person picked and opens it. Returns the sync folder inside it.
    func choose(_ picked: URL) throws -> URL
    func relinquish()
}

public extension SyncFolderSource {
    func resolveAsync() async -> SyncFolderResolution {
        resolve()
    }
}

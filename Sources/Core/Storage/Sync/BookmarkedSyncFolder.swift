// SPDX-License-Identifier: MIT
import Foundation
import os

private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "SyncFolder")

/// The URL calls a bookmarked folder needs, so a test can count starts and stops and stage a stale link.
public protocol SecurityScopedBookmarks: Sendable {
    func bookmark(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool)
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
    func isReachableFolder(_ url: URL) -> Bool
}

public struct SystemBookmarks: SecurityScopedBookmarks {
    public init() {}

    public func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }

    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    public func isReachableFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// The folder an iPhone or iPad was given in the file picker (ADR 0046), kept as a bookmark in `Setting`. The person
/// picks the folder that holds, or will hold, "Pesto Sync", as the Mac's default does; a folder that is already a sync
/// folder is used as it is, which is what a Mac's Change… makes.
@MainActor
public final class BookmarkedSyncFolder: SyncFolderSource {
    public nonisolated static let folderName = "Pesto Sync"

    private let defaults: UserDefaults
    private let bookmarks: any SecurityScopedBookmarks
    /// The picked folder while it is open, and whether the system granted a scope that must be stopped. A folder inside
    /// the app's own container needs no scope, and stopping one that was never started would unbalance the count.
    private struct OpenFolder {
        let picked: URL
        let root: URL
        let scoped: Bool
    }

    private var open: OpenFolder?

    public init(defaults: UserDefaults, bookmarks: any SecurityScopedBookmarks = SystemBookmarks()) {
        self.defaults = defaults
        self.bookmarks = bookmarks
    }

    public var hasChosenFolder: Bool {
        !defaults.value(for: Setting.syncFolderBookmark).isEmpty
    }

    private nonisolated static func isSyncFolder(_ url: URL) -> Bool {
        let layout = SyncFolderLayout(root: url)
        return FileManager.default.fileExists(atPath: layout.devices.path)
            || FileManager.default.fileExists(atPath: layout.vault(epoch: 1).path)
    }

    public nonisolated static func syncRoot(forPicked picked: URL) -> URL {
        if picked.lastPathComponent == folderName || isSyncFolder(picked) { return picked }
        let direct = picked.appendingPathComponent(folderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let pestoDir = picked.appendingPathComponent("Pesto", isDirectory: true)
        let nested = pestoDir.appendingPathComponent(folderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: nested.path) { return nested }
        if isSyncFolder(pestoDir) { return pestoDir }
        if FileManager.default.fileExists(atPath: pestoDir.path) { return nested }
        return direct
    }

    public static func suggestedPickerDirectory() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    public func resolve() -> SyncFolderResolution {
        if let open { return .ready(open.root) }
        let stored: String = defaults.value(for: Setting.syncFolderBookmark)
        guard !stored.isEmpty else { return .notChosen }
        guard let data = Data(base64Encoded: stored) else { return .needsRepair(.unresolvable) }
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try bookmarks.resolve(data)
        } catch {
            logger.error("The sync folder's bookmark did not resolve: \(error.localizedDescription, privacy: .public)")
            return .needsRepair(.unresolvable)
        }
        guard let root = openFolder(resolved.url) else {
            return .needsRepair(resolved.isStale ? .stale : .unreachable)
        }
        if resolved.isStale {
            // Apple's pattern: a stale bookmark that still opens the folder is made again while the folder is open.
            do {
                let renewed = try bookmarks.bookmark(for: resolved.url)
                defaults.set(renewed.base64EncodedString(), for: Setting.syncFolderBookmark)
            } catch {
                logger.error("The stale sync bookmark was not renewed: \(error.localizedDescription, privacy: .public)")
                relinquish()
                return .needsRepair(.stale)
            }
        }
        return .ready(root)
    }

    public func resolveAsync() async -> SyncFolderResolution {
        if let open { return .ready(open.root) }
        let stored: String = defaults.value(for: Setting.syncFolderBookmark)
        guard !stored.isEmpty else { return .notChosen }
        guard let data = Data(base64Encoded: stored) else { return .needsRepair(.unresolvable) }
        let result = await Self.resolveOffMainActor(data, bookmarks: bookmarks)
        switch result {
        case let .ready(picked, root, scoped, renewedBookmark):
            if let renewedBookmark {
                defaults.set(renewedBookmark.base64EncodedString(), for: Setting.syncFolderBookmark)
            }
            open = OpenFolder(picked: picked, root: root, scoped: scoped)
            return .ready(root)
        case let .needsRepair(problem):
            return .needsRepair(problem)
        }
    }

    private enum OffMainResolution {
        case ready(picked: URL, root: URL, scoped: Bool, renewedBookmark: Data?)
        case needsRepair(SyncFolderProblem)
    }

    @concurrent
    private static func resolveOffMainActor(
        _ data: Data, bookmarks: any SecurityScopedBookmarks
    ) async
        -> OffMainResolution
    {
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try bookmarks.resolve(data)
        } catch {
            logger.error("The sync folder's bookmark did not resolve: \(error.localizedDescription, privacy: .public)")
            return .needsRepair(.unresolvable)
        }
        let scoped = bookmarks.startAccessing(resolved.url)
        guard bookmarks.isReachableFolder(resolved.url) else {
            if scoped { bookmarks.stopAccessing(resolved.url) }
            return .needsRepair(resolved.isStale ? .stale : .unreachable)
        }
        let root = syncRoot(forPicked: resolved.url)
        var renewedBookmark: Data?
        if resolved.isStale {
            do {
                renewedBookmark = try bookmarks.bookmark(for: resolved.url)
            } catch {
                logger.error("The stale sync bookmark was not renewed: \(error.localizedDescription, privacy: .public)")
                if scoped { bookmarks.stopAccessing(resolved.url) }
                return .needsRepair(.stale)
            }
        }
        return .ready(picked: resolved.url, root: root, scoped: scoped, renewedBookmark: renewedBookmark)
    }

    public func choose(_ picked: URL) throws -> URL {
        relinquish()
        let scoped = bookmarks.startAccessing(picked)
        let data: Data
        do {
            data = try bookmarks.bookmark(for: picked)
        } catch {
            if scoped { bookmarks.stopAccessing(picked) }
            throw error
        }
        if scoped { bookmarks.stopAccessing(picked) }
        defaults.set(data.base64EncodedString(), for: Setting.syncFolderBookmark)
        guard let root = openFolder(picked) else { throw CocoaError(.fileReadNoPermission) }
        return root
    }

    public func relinquish() {
        guard let open else { return }
        if open.scoped { bookmarks.stopAccessing(open.picked) }
        self.open = nil
    }

    private func openFolder(_ picked: URL) -> URL? {
        let scoped = bookmarks.startAccessing(picked)
        guard bookmarks.isReachableFolder(picked) else {
            if scoped { bookmarks.stopAccessing(picked) }
            return nil
        }
        let root = Self.syncRoot(forPicked: picked)
        open = OpenFolder(picked: picked, root: root, scoped: scoped)
        return root
    }
}

// SPDX-License-Identifier: MIT
import Foundation
import Observation
import os

/// The apps other devices named in their sync catalogs (ADR 0068), kept on a device that cannot look an app up by
/// its bundle ID (an iPhone), so a card can show the app's icon and glow in its color. It holds what the history's
/// own plain columns already say (a bundle ID and a name) plus an icon and a color; no clip and no clip's text. One
/// owner-only file in the support folder; Clear Everything and Leave Sync empty it.
@MainActor
@Observable
public final class SourceAppCatalogStore {
    public static let maxEntries = 256

    @ObservationIgnored public let fileURL: URL
    private var entries: [String: SyncAppCatalog.Entry] = [:]
    /// Most recently arrived first, so the bound drops the apps seen longest ago.
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "SourceApps")

    public init(directory: URL = AppPaths.supportDirectory) {
        fileURL = directory.appendingPathComponent("source-apps.json")
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([SyncAppCatalog.Entry].self, from: data) else { return }
        for entry in SyncAppCatalog.bounded(saved).prefix(Self.maxEntries) {
            entries[entry.bundleID] = entry
            order.append(entry.bundleID)
        }
    }

    public var count: Int {
        entries.count
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    public func entry(for bundleID: String?) -> SyncAppCatalog.Entry? {
        bundleID.flatMap { entries[$0] }
    }

    public func merge(_ arrived: [SyncAppCatalog.Entry]) {
        let valid = SyncAppCatalog.bounded(arrived)
        guard valid.contains(where: { entries[$0.bundleID] != $0 }) else { return }
        for entry in valid.reversed() {
            entries[entry.bundleID] = entry
            order.removeAll { $0 == entry.bundleID }
            order.insert(entry.bundleID, at: 0)
        }
        while order.count > Self.maxEntries, let dropped = order.popLast() {
            entries[dropped] = nil
        }
        save()
    }

    public func clear() {
        entries = [:]
        order = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        do {
            let list = order.compactMap { entries[$0] }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(list).write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            logger.error("The source apps were not saved: \(String(describing: error), privacy: .public)")
        }
    }
}

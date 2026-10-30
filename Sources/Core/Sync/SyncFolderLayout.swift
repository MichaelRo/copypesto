// SPDX-License-Identifier: MIT
import Foundation

/// Where things are in the sync folder. Every file has exactly one writer: a Mac writes only inside its own
/// `devices/<id>/`, and the vault files are written once.
public struct SyncFolderLayout: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var devices: URL {
        root.appendingPathComponent("devices", isDirectory: true)
    }

    public func vault(epoch: UInt32) -> URL {
        root.appendingPathComponent(SyncVault.fileName(epoch: epoch))
    }

    public func device(_ id: String) -> URL {
        devices.appendingPathComponent(id, isDirectory: true)
    }

    public func deviceRecord(_ id: String) -> URL {
        device(id).appendingPathComponent("device.pestodev")
    }

    public func log(_ id: String) -> URL {
        device(id).appendingPathComponent("log", isDirectory: true)
    }

    public func blobs(_ id: String) -> URL {
        device(id).appendingPathComponent("blobs", isDirectory: true)
    }

    public func head(_ id: String) -> URL {
        device(id).appendingPathComponent("head.pestohead")
    }

    public func identity(_ id: String) -> URL {
        device(id).appendingPathComponent("identity.pestokey")
    }

    public func joinRequest(_ id: String) -> URL {
        device(id).appendingPathComponent("join.pestojoin")
    }

    public func grants(_ id: String) -> URL {
        device(id).appendingPathComponent("grants", isDirectory: true)
    }

    public func segment(_ id: String, first: UInt64, last: UInt64) -> URL {
        log(id).appendingPathComponent(String(format: "%012llu-%012llu.pestolog", first, last))
    }

    public func vaultFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasPrefix("vault-") && $0.hasSuffix(".pestosync") }.sorted()
            .map { root.appendingPathComponent($0) }
    }

    /// `left/<device id>`: written by a Mac that used Leave Sync before it removes its own folder. An absent folder
    /// alone says nothing (it may not have finished downloading), so the others act on this marker only.
    public func leftMarker(_ id: String) -> URL {
        root.appendingPathComponent("left", isDirectory: true).appendingPathComponent(id)
    }

    public func leftDeviceIDs() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("left").path)) ??
            []
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    public func deviceIDs() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: devices.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }
}

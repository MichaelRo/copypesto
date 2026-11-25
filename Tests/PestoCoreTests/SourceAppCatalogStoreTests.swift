// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The apps other devices named, kept on this device")
@MainActor
struct SourceAppCatalogStoreTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x02])

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pesto-apps-\(UUID().uuidString)")
    }

    private func entry(_ id: String, color: String = "#1796F2") -> SyncAppCatalog.Entry {
        SyncAppCatalog.Entry(bundleID: id, name: id.capitalized, colorHex: color, icon: Self.png)
    }

    @Test("what arrives is kept, survives a new store, and the newest wins for the same app")
    func whenMerged_thenKeptAndUpdated() throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SourceAppCatalogStore(directory: dir)
        store.merge([entry("safari"), entry("mail")])
        store.merge([entry("safari", color: "#0B8BFD")])
        #expect(store.entry(for: "safari")?.colorHex == "#0B8BFD")
        let reopened = SourceAppCatalogStore(directory: dir)
        #expect(reopened.entry(for: "mail")?.icon == Self.png)
        #expect(reopened.entry(for: "nothing") == nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: reopened.fileURL.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test("it never holds more than its bound, keeping the newest")
    func whenManyArrive_thenBounded() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SourceAppCatalogStore(directory: dir)
        for batch in 0..<3 {
            store.merge((0..<100).map { entry("app\(batch * 100 + $0)") })
        }
        #expect(store.count == SourceAppCatalogStore.maxEntries)
        #expect(store.entry(for: "app299") != nil)
        #expect(store.entry(for: "app99") == nil, "the oldest batch's least recent apps go first")
    }

    @Test("Clear empties it and its file")
    func whenCleared_thenGone() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SourceAppCatalogStore(directory: dir)
        store.merge([entry("safari")])
        store.clear()
        #expect(store.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}

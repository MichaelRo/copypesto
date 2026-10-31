// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Collection export and import")
@MainActor
struct CollectionExporterTests {
    private func setupContainer() throws -> ModelContainer {
        try ModelContainerSetup.makeInMemory()
    }

    @Test("exporting and importing a collection preserves metadata and items")
    func whenExported_thenImportPreservesCollection() async throws {
        let sourceContainer = try setupContainer()
        let collectionID = UUID()
        let board = Pinboard(
            id: collectionID,
            name: "Family Info",
            symbolName: "house",
            colorHex: "#3DAF60",
            sortOrder: 1
        )
        sourceContainer.mainContext.insert(board)

        let itemID = UUID()
        let item = ClipboardItem(
            id: itemID,
            timestamp: .now,
            type: .text,
            sourceBundleID: "com.apple.Notes",
            sourceAppName: "Notes",
            sourceDominantColorHex: nil,
            previewText: "Postal code: 90210",
            sensitivity: nil,
            sensitivityMaskedPreview: nil,
            contentHash: "dummyhash",
            perceptualHash: nil,
            byteSize: 20,
            deviceID: "mac",
            sequenceNumber: 1
        )
        item.collectionID = collectionID
        item.customTitle = "Home Postal Code"
        sourceContainer.mainContext.insert(item)
        try sourceContainer.mainContext.save()

        let exporter = HistoryExporter(modelContainer: sourceContainer)
        let exportedData = try await exporter.exportCollection(id: collectionID)
        #expect(!exportedData.isEmpty)

        let destContainer = try setupContainer()
        let importer = HistoryExporter(modelContainer: destContainer)
        let result = try await importer.importCollection(from: exportedData)

        #expect(result.itemsImported == 1)
        #expect(result.collectionID == collectionID)

        let importedBoards = try destContainer.mainContext.fetch(FetchDescriptor<Pinboard>())
        #expect(importedBoards.count == 1)
        #expect(importedBoards.first?.name == "Family Info")
        #expect(importedBoards.first?.symbolName == "house")

        let importedItems = try destContainer.mainContext.fetch(FetchDescriptor<ClipboardItem>())
        #expect(importedItems.count == 1)
        #expect(importedItems.first?.customTitle == "Home Postal Code")
        #expect(importedItems.first?.collectionID == collectionID)
    }

    @Test("exporting a nonexistent collection throws an error")
    func whenMissingCollection_thenThrows() async throws {
        let container = try setupContainer()
        let exporter = HistoryExporter(modelContainer: container)
        await #expect(throws: Error.self) {
            try await exporter.exportCollection(id: UUID())
        }
    }

    @Test("writing a collection puts a file that imports back where asked, and a missing one leaves no file")
    func whenWritten_thenTheFileImportsBack() async throws {
        let container = try setupContainer()
        let collectionID = UUID()
        container.mainContext.insert(
            Pinboard(id: collectionID, name: "Snippets", symbolName: "star", colorHex: "#3DAF60", sortOrder: 0)
        )
        try container.mainContext.save()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = HistoryExporter(modelContainer: container)

        let file = folder.appendingPathComponent("Snippets.json")
        try await exporter.writeCollection(id: collectionID, to: file)
        let mode = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        #expect(mode & 0o077 == 0, "a collection export carries titles, notes and tags: owner-only (R-08)")
        let result = try await HistoryExporter(modelContainer: setupContainer())
            .importCollection(from: Data(contentsOf: file))
        #expect(result.collectionID == collectionID)

        let missing = folder.appendingPathComponent("Missing.json")
        await #expect(throws: Error.self) { try await exporter.writeCollection(id: UUID(), to: missing) }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}

// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The .pesto collection file type")
struct CollectionFileTypeTests {
    private func info() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/Resources/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("the identifier is built from the app's identity")
    func identifier_followsTheBundleID() {
        #expect(CollectionFileType.identifier == "\(AppIdentity.bundleID).collection")
    }

    @Test("Info.plist exports the type as JSON with the pesto extension")
    func infoPlist_exportsTheType() throws {
        let declarations = try #require(info()["UTExportedTypeDeclarations"] as? [[String: Any]])
        let declaration = try #require(declarations.first {
            $0["UTTypeIdentifier"] as? String == CollectionFileType.identifier
        })
        let conformsTo = try #require(declaration["UTTypeConformsTo"] as? [String])
        #expect(Set(conformsTo) == ["public.json", "public.data"])
        let tags = try #require(declaration["UTTypeTagSpecification"] as? [String: Any])
        #expect(tags["public.filename-extension"] as? [String] == [CollectionFileType.fileExtension])
    }

    @Test("Info.plist makes Pesto the owner of the type as a viewer")
    func infoPlist_declaresTheDocumentType() throws {
        let documents = try #require(info()["CFBundleDocumentTypes"] as? [[String: Any]])
        let document = try #require(documents.first {
            ($0["LSItemContentTypes"] as? [String])?.contains(CollectionFileType.identifier) == true
        })
        #expect(document["CFBundleTypeRole"] as? String == "Viewer")
        #expect(document["LSHandlerRank"] as? String == "Owner")
    }

    @Test("a .pesto or .json file is accepted, anything else is not, and a huge one is named too large")
    func openVerdict_judgesNameAndSize() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func make(_ name: String, size: Int = 10) throws -> URL {
            let url = folder.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data(count: size))
            return url
        }

        #expect(try CollectionFileType.openVerdict(for: make("Work.pesto")) == .accept)
        #expect(try CollectionFileType.openVerdict(for: make("Work.PESTO")) == .accept)
        #expect(try CollectionFileType.openVerdict(for: make("old.json")) == .accept)
        #expect(try CollectionFileType.openVerdict(for: make("photo.png")) == .notACollectionFile)
        #expect(CollectionFileType.openVerdict(for: folder.appendingPathComponent("gone.pesto")) == .notACollectionFile)
        #expect(try CollectionFileType
            .openVerdict(for: #require(URL(string: "https://example.com/a.pesto"))) == .notACollectionFile)
        let directory = folder.appendingPathComponent("Folder.pesto")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(CollectionFileType.openVerdict(for: directory) == .notACollectionFile)
        let huge = try make("huge.pesto", size: 0)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(HistoryExporter.maxImportBytes + 1))
        try handle.close()
        #expect(CollectionFileType.openVerdict(for: huge) == .tooLarge)
    }

    @Test("the summary names the collection and counts its clips without importing, and refuses a newer file")
    func summary_readsNameAndCount() throws {
        func file(version: Int) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "version": version,
                "collection": [
                    "id": UUID().uuidString,
                    "name": "Recipes",
                    "symbolName": "star",
                    "colorHex": "#3DAF60",
                    "isSmart": false
                ],
                "items": [["id": UUID().uuidString], ["id": UUID().uuidString]]
            ] as [String: Any])
        }

        let summary = try CollectionFileType.summary(of: file(version: 2))
        #expect(summary == .init(name: "Recipes", clipCount: 2))
        #expect(throws: HistoryExporter.ImportError.unsupportedVersion) {
            try CollectionFileType.summary(of: file(version: 9))
        }
        #expect(throws: Error.self) { try CollectionFileType.summary(of: Data("not json".utf8)) }
    }

    @MainActor
    @Test("a collection written with the pesto extension imports back")
    func roundTrip_throughAPestoFile() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let boardID = UUID()
        container.mainContext.insert(
            Pinboard(id: boardID, name: "Shared", symbolName: "star", colorHex: "#3DAF60", sortOrder: 0)
        )
        try container.mainContext.save()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Shared-\(UUID().uuidString).pesto")
        defer { try? FileManager.default.removeItem(at: url) }
        try await HistoryExporter(modelContainer: container).writeCollection(id: boardID, to: url)
        #expect(CollectionFileType.openVerdict(for: url) == .accept)

        let destination = try ModelContainerSetup.makeInMemory()
        let result = try await HistoryExporter(modelContainer: destination).importCollection(
            fromFile: url, storage: StorageService(modelContainer: destination, environment: .testing())
        )

        #expect(result.collectionID == boardID)
    }
}

// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

/// AGENTS.md security invariant 2: "All blob storage is encrypted at rest ... on-disk bytes differ from plaintext."
/// Nothing tested that against a real store on disk; the crypto tests only used an in-memory key.
@Suite("On-disk store contains no plaintext")
struct OnDiskEncryptionTests {
    private let snippet = "dear customer, your reference is \(UUID().uuidString)"

    private func sha(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func textCapture(_ text: String, bundleID: String? = nil) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data(text.utf8),
            payloadString: text,
            frontmostBundleID: bundleID,
            contentHash: sha(text)
        )
    }

    /// Every byte of every file under `directory`: the SQLite file, its WAL and shm, and external storage.
    private func allBytes(under directory: URL) throws -> [(name: String, data: Data)] {
        let enumerator = try #require(FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ))
        var files: [(String, Data)] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            try files.append((url.lastPathComponent, Data(contentsOf: url)))
        }
        return files
    }

    private func contains(_ needle: String, in files: [(name: String, data: Data)]) -> Bool {
        let bytes = Data(needle.utf8)
        return files.contains { $0.data.range(of: bytes) != nil }
    }

    @Test("clip text, URLs and image bytes never appear in the files the store writes")
    func store_holdsOnlyCiphertext() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-ondisk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = try ModelContainer(
            for: ClipboardItem.self, ClipboardBlob.self, DeletedItemTombstone.self, Pinboard.self,
            configurations: ModelConfiguration(
                "clips",
                url: directory.appendingPathComponent("clips.store"),
                cloudKitDatabase: .none
            )
        )
        let service = StorageService(modelContainer: container)
        let text = "quarterly notes \(UUID().uuidString)"
        let link = "https://example.com/reset?token=\(UUID().uuidString)"
        let imageMarker = "IMAGE-BYTES-\(UUID().uuidString)"
        let controlBundleID = "com.example.control-\(UUID().uuidString)"
        let title = "title-\(UUID().uuidString)"
        let note = "note-\(UUID().uuidString)"
        let tag = "tag-\(UUID().uuidString)"
        let pageTitle = "page-\(UUID().uuidString)"
        let vectorMarker = Data("VECTOR-BYTES-\(UUID().uuidString)".utf8)

        try await service.ingest(textCapture(text, bundleID: controlBundleID))
        try await service.ingest(textCapture(link))
        _ = try await service.addSnippet(snippet)
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.png",
            payload: Data(imageMarker.utf8),
            payloadString: nil,
            contentHash: sha(imageMarker)
        ))
        let context = ModelContext(container)
        let annotated = try #require(context.fetch(FetchDescriptor<ClipboardItem>())
            .first { $0.sourceBundleID == controlBundleID })
        annotated.customTitle = title
        annotated.userNote = note
        annotated.tags = [tag]
        annotated.ogTitle = pageTitle
        annotated.embeddingData = vectorMarker
        try context.save()
        // A save is not a checkpoint: the bytes may still be in the write-ahead log, which is scanned too.
        let files = try allBytes(under: directory)

        #expect(
            contains(controlBundleID, in: files),
            "control: the scan must be able to see a field stored in the clear"
        )
        #expect(!contains(text, in: files), "clip text is on disk in plaintext")
        #expect(!contains(link, in: files), "a URL is on disk in plaintext")
        #expect(!contains(snippet, in: files), "a snippet is on disk in plaintext")
        #expect(!contains(title, in: files), "a title is on disk in plaintext")
        #expect(!contains(note, in: files), "a note is on disk in plaintext")
        #expect(!contains(tag, in: files), "a tag is on disk in plaintext")
        #expect(!contains(pageTitle, in: files), "a page title is on disk in plaintext")
        #expect(!contains(imageMarker, in: files), "image bytes are on disk in plaintext")
        #expect(
            !files.contains { $0.data.range(of: vectorMarker) != nil },
            "a search vector is on disk in plaintext"
        )
        // A bare SHA-256 of the clip is a fingerprint anyone with the file can test guesses against (an SSN has only
        // about a billion values). The stored hash must be keyed.
        #expect(!contains(sha(text), in: files), "an unkeyed hash of the text is on disk")
        #expect(!contains(sha(link), in: files), "an unkeyed hash of the URL is on disk")
        #expect(!contains(sha(imageMarker), in: files), "an unkeyed hash of the image is on disk")
    }

    @Test("a clip big enough to be written to its own external file leaves only ciphertext there too")
    func store_externalFilesHoldOnlyCiphertext() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-ondisk-large-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: ClipboardItem.self, ClipboardBlob.self, DeletedItemTombstone.self, Pinboard.self,
            configurations: ModelConfiguration(
                "clips", url: directory.appendingPathComponent("clips.store"), cloudKitDatabase: .none
            )
        )
        let service = StorageService(modelContainer: container)
        let marker = "LARGE-CLIP-\(UUID().uuidString)"
        let large = String(repeating: marker + " ", count: 20_000)

        try await service.ingest(textCapture(large))
        let files = try allBytes(under: directory)

        let databaseFiles = ["clips.store", "clips.store-wal", "clips.store-shm"]
        #expect(
            files.contains { !databaseFiles.contains($0.name) },
            "control: the clip should have been written to an external file, or this proves nothing"
        )
        #expect(!contains(marker, in: files), "a large clip is on disk in plaintext")
    }

    @Test("text wrapped as rgb(...) or hsl(...) is not a colour and never lands in the store in the clear (R-01)")
    func store_wrappedSecretIsNotKeptAsAColour() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-ondisk-colour-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: ClipboardItem.self, ClipboardBlob.self, DeletedItemTombstone.self, Pinboard.self,
            configurations: ModelConfiguration(
                "clips", url: directory.appendingPathComponent("clips.store"), cloudKitDatabase: .none
            )
        )
        let service = StorageService(modelContainer: container)
        let first = "password=hunter2-\(UUID().uuidString)"
        let second = "AKIAIOSFODNN7EXAMPLE secret \(UUID().uuidString)"
        let colour = "rgb(12, 34, 56)"

        try await service.ingest(textCapture("rgb(\(first))"))
        try await service.ingest(textCapture("hsl(\(second))"))
        try await service.ingest(textCapture(colour))
        let files = try allBytes(under: directory)

        #expect(contains(colour, in: files), "control: a real colour is the one preview kept in the clear")
        #expect(!contains(first, in: files), "a wrapped password is on disk in plaintext")
        #expect(!contains(second, in: files), "a wrapped key is on disk in plaintext")
    }
}

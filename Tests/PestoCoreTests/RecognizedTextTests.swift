// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@MainActor
@Suite("Recognized text: the size cap and which pictures offer it")
struct RecognizedTextTests {
    private func makeStore() -> (RecognizedTextStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-ocr-\(UUID().uuidString)", isDirectory: true)
        let key = SymmetricKey(size: .bits256)
        return (RecognizedTextStore(directory: directory, key: { key }), directory)
    }

    private func picture(preview: String, secret: SensitivityCategory? = nil) throws -> ClipboardItem {
        let item = ClipboardItem(
            type: .image, previewText: "", contentHash: UUID().uuidString, byteSize: 1000, deviceID: "test",
            sequenceNumber: 1
        )
        if let secret {
            item.sensitivityRaw = secret.rawValue
        }
        let sealed = try BlobEncryption().encrypt(
            Data(preview.utf8), associatedData: BlobEncryption.associatedData(itemID: item.id, field: .preview)
        )
        item.previewCiphertext = sealed.ciphertext
        item.previewNonce = sealed.nonce
        item.previewAADBound = true
        return item
    }

    private let long = String(repeating: "recognized ", count: 80)

    // MARK: Cap

    @Test("text under the cap is kept whole")
    func whenUnderCap_thenUnchanged() {
        #expect(RecognizedText.capped("a short text") == "a short text")
    }

    @Test("text over the cap is cut to the byte limit, on a character boundary")
    func whenOverCap_thenCutOnBoundary() {
        let text = String(repeating: "数", count: 50_000)
        let capped = RecognizedText.capped(text)
        #expect(capped.utf8.count <= RecognizedText.maxBytes)
        #expect(capped.utf8.count > RecognizedText.maxBytes - 4)
        #expect(capped.allSatisfy { $0 == "数" })
        let ascii = RecognizedText.capped(String(repeating: "x", count: RecognizedText.maxBytes + 5))
        #expect(ascii.utf8.count == RecognizedText.maxBytes)
    }

    @Test("a file is kept when the preview would cut the text, and not otherwise")
    func whenPreviewCutsText_thenNeedsFile() {
        #expect(RecognizedText.needsFile(String(repeating: "x", count: CardPreviewText.previewLength)))
        #expect(!RecognizedText.needsFile(String(repeating: "x", count: CardPreviewText.previewLength - 1)))
    }

    // MARK: Offered

    @Test("a picture with a file offers it and copies the file's text")
    func whenFileExists_thenOfferedAndRead() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try picture(preview: String(long.prefix(500)))
        try store.save(long, for: item.id)

        #expect(RecognizedText.isOffered(for: item, store: store))
        #expect(RecognizedText.text(of: item, store: store) == long)
    }

    @Test("a short preview is the whole text, so an old picture offers it without a file")
    func whenShortPreviewAndNoFile_thenPreviewIsTheText() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try picture(preview: "Boarding pass\nGate 12")

        #expect(RecognizedText.isOffered(for: item, store: store))
        #expect(RecognizedText.text(of: item, store: store) == "Boarding pass\nGate 12")
    }

    @Test("an old picture whose preview is exactly 500 characters is not offered: it may have been cut")
    func whenFullPreviewAndNoFile_thenHidden() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try picture(preview: String(repeating: "y", count: CardPreviewText.previewLength))

        #expect(!RecognizedText.isOffered(for: item, store: store))
        #expect(RecognizedText.text(of: item, store: store) == nil)
    }

    @Test("a preview cut at 500 characters that ends in a line break is not offered either")
    func whenCutPreviewEndsInLineBreak_thenHidden() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try picture(preview: String(repeating: "y", count: CardPreviewText.previewLength - 1) + "\n")

        #expect(!RecognizedText.isOffered(for: item, store: store))
        #expect(RecognizedText.text(of: item, store: store) == nil)
    }

    @Test("a picture with no text is not offered")
    func whenNoText_thenHidden() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try !RecognizedText.isOffered(for: picture(preview: ""), store: store))
        #expect(try !RecognizedText.isOffered(for: picture(preview: "  \n "), store: store))
    }

    @Test("a file that will not open writes nothing, and the preview is not a fallback")
    func whenFileUnreadable_thenNoFallback() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try picture(preview: "short preview")
        try store.save(long, for: item.id)
        let other = RecognizedTextStore(directory: directory, key: { SymmetricKey(size: .bits256) })

        #expect(RecognizedText.text(of: item, store: other) == nil)
    }

    @Test("a secret, a filtered picture and one still being read offer nothing, even with a file")
    func whenNotEligible_thenHidden() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secret = try picture(preview: "short", secret: .apiKey)
        let filtered = try picture(preview: "short")
        filtered.isNSFW = true
        let pending = try picture(preview: "short")
        pending.analysisPending = true
        for item in [secret, filtered, pending] {
            try store.save(long, for: item.id)
            #expect(!RecognizedText.isOffered(for: item, store: store))
            #expect(RecognizedText.text(of: item, store: store) == nil)
        }
    }

    @Test("only a picture offers recognized text")
    func whenNotAPicture_thenHidden() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try picture(preview: "short")
        item.typeRaw = ClipboardType.text.rawValue
        #expect(!RecognizedText.isOffered(for: item, store: store))
    }

    @Test("asking 5,000 pictures whether they read text, as VoiceOver's action list does, costs well under a frame")
    func whenAskedOfManyPictures_thenCheap() throws {
        let items = try (0..<5000).map { _ in try picture(preview: "Boarding pass gate B22") }
        let cold = ContinuousClock.now
        for item in items {
            _ = RecognizedText.hasText(item)
        }
        let coldElapsed = ContinuousClock.now - cold
        let warm = ContinuousClock.now
        for item in items {
            _ = RecognizedText.hasText(item)
        }
        let warmElapsed = ContinuousClock.now - warm
        #expect(coldElapsed < .milliseconds(500), "cold took \(coldElapsed)")
        #expect(warmElapsed < .milliseconds(100), "warm took \(warmElapsed)")
    }
}

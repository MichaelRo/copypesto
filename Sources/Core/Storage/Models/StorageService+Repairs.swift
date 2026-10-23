// SPDX-License-Identifier: MIT
import AppKit
import CryptoKit
import SwiftData

public extension StorageService {
    /// Fixes clips stored wrong by two old bugs (ADR 0002). A number such as `20231234`, a reference such as `#178` or
    /// a word such as `decade` was read as a colour (and a colour keeps its preview in the clear): every colour clip
    /// is read again with today's rules. A rich-text record imported from Paste kept an RTF blob and no
    /// preview, so its card showed a title and nothing else. Idempotent; a clip that cannot be fixed is left alone.
    func repairMisreadClips() async throws -> (reclassified: Int, rebuilt: Int) {
        let reclassified = try await reclassifyNumbersStoredAsColours()
        let rebuilt = try await rebuildEmptyRichTextClips()
        try removeSampleSnippetsPinboard()
        return (reclassified, rebuilt)
    }

    /// Rewrites the masks an older version stored, which repeated the badge's label ("API key •••• (45 characters
    /// hidden)"), to dots and a count. A string rewrite, not a new scan: it needs no key and covers a picture whose
    /// text
    /// held a secret. Idempotent; returns how many clips changed.
    func modernizeSecretMasks() async throws -> Int {
        var changed = 0
        try await forEachClip(matching: FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.sensitivityMaskedPreview != nil }
        )) { item in
            guard let stored = item.sensitivityMaskedPreview else { return }
            let modern = SensitiveContentDetector.modernisedMask(stored)
            guard modern != stored else { return }
            item.sensitivityMaskedPreview = modern
            if item.previewText == stored { item.previewText = modern }
            changed += 1
        }
        return changed
    }

    private func removeSampleSnippetsPinboard() throws {
        let snippetsName = FirstRunSamples.collectionName
        let boards = try modelContext.fetch(FetchDescriptor<Pinboard>(
            predicate: #Predicate { $0.name == snippetsName && !$0.isSmart }
        ))
        for board in boards {
            let boardID = board.id
            let members = try modelContext.fetch(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.collectionID == boardID }
            ))
            let onlySamples = members.allSatisfy { $0.customTitle == FirstRunSamples.snippetTitle }
            guard onlySamples else { continue }
            for member in members {
                member.collectionID = nil
            }
            modelContext.delete(board)
        }
        if modelContext.hasChanges {
            try saveOrRollback()
        }
    }

    private func reclassifyNumbersStoredAsColours() async throws -> Int {
        let colorRaw = ClipboardType.color.rawValue
        var changed = 0
        try await forEachClip(matching: FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.typeRaw == colorRaw && $0.previewCiphertext == nil }
        )) { item in
            let text = item.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let reading = ContentClassifier.classify(text: text)
            guard reading.type != .color || !ColorPreviewPolicy.mayStoreInTheClear(text) else { return }
            if let sensitivity = SensitiveContentDetector.detect(in: text) {
                item.sensitivityRaw = sensitivity.category.rawValue
                item.sensitivityMaskedPreview = sensitivity.maskedPreview
                item.previewText = sensitivity.maskedPreview
            } else {
                let envelope = try sealPreview(Data(item.previewText.prefix(500).utf8), itemID: item.id)
                item.previewCiphertext = envelope.ciphertext
                item.previewNonce = envelope.nonce
                item.previewAADBound = true
                item.previewText = ""
            }
            item.typeRaw = reading.type.rawValue
            item.detectedLanguage = reading.type == .code || reading.type == .text ? reading.detectedLanguage : nil
            item.textLength = text.count
            changed += 1
        }
        return changed
    }

    private func rebuildEmptyRichTextClips() async throws -> Int {
        let textRaw = ClipboardType.text.rawValue
        let ids = try modelContext.fetchIdentifiers(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate {
                $0.typeRaw == textRaw && $0.previewCiphertext == nil && $0.previewText.isEmpty && $0
                    .sensitivityRaw == nil
            }
        ))
        var rebuilt = 0
        for start in stride(from: 0, to: ids.count, by: 50) {
            let page = Array(ids[start..<min(start + 50, ids.count)])
            let items = try modelContext.fetch(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { page.contains($0.persistentModelID) }
            ))
            for item in items {
                let didRebuild = try await rebuildRichTextClip(item)
                if didRebuild { rebuilt += 1 }
            }
            try saveOrRollback()
            await Task.yield()
        }
        return rebuilt
    }

    private func rebuildRichTextClip(_ item: ClipboardItem) async throws -> Bool {
        guard let blob = item.blob,
              let kind = Self.richTextType(for: blob.mimeType),
              let data = blob.decryptedData(),
              let flattened = await RichTextFlattener.plainText(from: data, type: kind) else { return false }
        let text = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let payload = Data(text.utf8)
        let blobEnvelope = try encryption.encrypt(
            payload, associatedData: BlobEncryption.associatedData(itemID: item.id, field: .blob)
        )
        let classified = ContentClassifier.classify(text: text)
        let sensitivity = SensitiveContentDetector.detect(in: text)
        let preview = sensitivity?.maskedPreview ?? String(text.prefix(500))
        let sealsPreview = sensitivity == nil && ColorPreviewPolicy.sealsPreview(of: classified.type, preview: preview)

        blob.encryptedData = blobEnvelope.ciphertext
        blob.nonceData = blobEnvelope.nonce
        blob.mimeType = NSPasteboard.PasteboardType.string.rawValue
        blob.aadBound = true
        item.typeRaw = classified.type.rawValue
        item.detectedLanguage = classified.detectedLanguage
        item.byteSize = payload.count
        item.textLength = classified.type == .text || classified.type == .code ? text.count : 0
        let digest = payload.sha256Hex
        item.contentHash = ContentHash.stored(digest, key: try? encryption.loadOrCreateKey())
        item.sensitivityRaw = sensitivity?.category.rawValue
        item.sensitivityMaskedPreview = sensitivity?.maskedPreview
        if sealsPreview {
            let envelope = try sealPreview(Data(preview.utf8), itemID: item.id)
            item.previewCiphertext = envelope.ciphertext
            item.previewNonce = envelope.nonce
            item.previewAADBound = true
            item.previewText = ""
        } else {
            item.previewText = preview
        }
        return true
    }

    private static func richTextType(for mimeType: String) -> NSPasteboard.PasteboardType? {
        switch mimeType {
        case NSPasteboard.PasteboardType.rtf.rawValue: .rtf
        case NSPasteboard.PasteboardType.rtfd.rawValue: .rtfd
        default: nil
        }
    }
}

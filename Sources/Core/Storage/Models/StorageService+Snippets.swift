// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData

public extension StorageService {
    /// Saves text as a snippet: it goes through `ingest` like any copy (sealed preview and blob, sensitivity masking,
    /// searchable, part of every backup) and is then pinned. Text the history already holds is pinned in place instead
    /// of becoming a second clip. Returns nil when ingest kept nothing.
    @discardableResult
    func addSnippet(_ text: String, title: String? = nil) async throws -> UUID? {
        guard let added = try await insertSnippet(text, title: title, recordsEdit: true) else { return nil }
        if added.created { undoHistory.record(UndoEntry(.clipsAdded(AddedClips(kind: .snippet, ids: [added.id])))) }
        return added.id
    }

    /// Saves several snippets as one action, which one Undo takes back. Returns how many were kept.
    func addSnippets(_ snippets: [(text: String, title: String?)]) async -> Int {
        var kept = 0
        var created: [UUID] = []
        for snippet in snippets {
            guard let added = try? await insertSnippet(snippet.text, title: snippet.title, recordsEdit: false) else {
                continue
            }
            kept += 1
            if added.created { created.append(added.id) }
        }
        if UndoPolicy.canHold(clipCount: created.count) {
            undoHistory.record(UndoEntry(.clipsAdded(AddedClips(kind: .snippet, ids: created))))
        }
        return kept
    }

    private func insertSnippet(
        _ text: String, title: String?, recordsEdit: Bool
    ) async throws
    -> (id: UUID, created: Bool)? {
        let payload = Data(text.utf8)
        let hash = payload.sha256Hex
        let forms = ContentHash.candidates(for: hash, key: try? encryption.loadOrCreateKey())
        let descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { forms.contains($0.contentHash) })
        let before = try modelContext.fetch(descriptor).first.map(ClipFieldState.init)
        try await ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text, contentHash: hash
        ))
        guard let item = try modelContext.fetch(descriptor).first else { return nil }
        item.isPinned = true
        if let title, item.customTitle == nil { item.customTitle = title }
        try saveOrRollback()
        if let before, recordsEdit { recordEdits([(item, before)]) }
        return (item.id, before == nil)
    }

    /// Replaces a snippet's title and text. The text is sealed the way ingest seals a copy (blob, preview, hash,
    /// sensitivity masking), so an edited snippet is as private as a new one. Returns false when no such clip exists or
    /// the text is empty; throws `ClipSizePolicy.TooLarge` for a text over the limit.
    @discardableResult
    func updateSnippet(id: UUID, title: String?, text: String) throws -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else { return false }
        let before = ClipSnapshot(item: item, linkPreviewFile: nil)
        let payload = Data(text.utf8)
        let typeIdentifier = "public.utf8-plain-text"
        if ClipSizePolicy.isTooLarge(byteCount: payload.count, typeIdentifier: typeIdentifier) {
            throw ClipSizePolicy.TooLarge(message: ClipSizePolicy.message(
                byteCount: payload.count, typeIdentifier: typeIdentifier
            ))
        }
        let envelope = try encryption.encrypt(
            payload, associatedData: BlobEncryption.associatedData(itemID: id, field: .blob)
        )
        let blob = item.blob ?? ClipboardBlob(
            encryptedData: envelope.ciphertext,
            nonceData: envelope.nonce,
            mimeType: typeIdentifier
        )
        blob.encryptedData = envelope.ciphertext
        blob.nonceData = envelope.nonce
        blob.mimeType = typeIdentifier
        blob.aadBound = true
        if item.blob == nil {
            item.blob = blob
            modelContext.insert(blob)
        }
        try applySnippetText(text, payload: payload, to: item)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        item.customTitle = trimmedTitle?.isEmpty == false ? trimmedTitle : nil
        try saveOrRollback()
        recordReplacement(of: item, before: before)
        PreviewTextCache.shared.clear()
        lastItemStore.clear(ifItemID: id)
        return true
    }

    private func applySnippetText(_ text: String, payload: Data, to item: ClipboardItem) throws {
        let classified = ContentClassifier.classify(text: text)
        let sensitivity = SensitiveContentDetector.detect(in: text)
        item.typeRaw = (classified.type == .code ? ClipboardType.code : .text).rawValue
        item.detectedLanguage = classified.type == .code || classified.type == .text ? classified.detectedLanguage : nil
        item.byteSize = payload.count
        item.textLength = text.count
        item.embeddingData = nil
        let digest = payload.sha256Hex
        item.contentHash = ContentHash.stored(digest, key: try? encryption.loadOrCreateKey())
        item.sensitivityRaw = sensitivity?.category.rawValue
        item.sensitivityMaskedPreview = sensitivity?.maskedPreview
        if let sensitivity {
            item.previewText = sensitivity.maskedPreview
            item.previewCiphertext = nil
            item.previewNonce = nil
            item.previewAADBound = false
        } else {
            let sealed = try sealPreview(Data(String(text.prefix(500)).utf8), itemID: item.id)
            item.previewText = ""
            item.previewCiphertext = sealed.ciphertext
            item.previewNonce = sealed.nonce
            item.previewAADBound = true
        }
    }

    /// Pins the clip if it is not pinned and unpins it if it is. A shortcut only works for a pinned clip, so unpinning
    /// frees it. Returns the new state, or nil when no such clip exists.
    @discardableResult
    func togglePinned(id: UUID) throws -> Bool? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else { return nil }
        let before = ClipFieldState(item)
        item.isPinned.toggle()
        if !item.isPinned { item.pinnedHotkeyIndex = nil }
        try saveOrRollback()
        recordEdits([(item, before)])
        return item.isPinned
    }

    /// Gives the clip the shortcut ⌃`slot` (1 to 9), or takes its shortcut away with nil. The shortcut belongs to one
    /// clip, so another clip that held it loses it, and a clip given one is pinned. Returns false for a slot that does
    /// not exist or a clip that is not there.
    @discardableResult
    func assignHotkeySlot(_ slot: Int?, to id: UUID) throws -> Bool {
        if let slot, !(1...9).contains(slot) { return false }
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else { return false }
        var before = [(item: item, state: ClipFieldState(item))]
        if let slot {
            let holders = try modelContext.fetch(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.pinnedHotkeyIndex == slot }
            ))
            for other in holders where other.id != id {
                before.append((other, ClipFieldState(other)))
                other.pinnedHotkeyIndex = nil
            }
            item.isPinned = true
        }
        item.pinnedHotkeyIndex = slot
        try saveOrRollback()
        recordEdits(before)
        return true
    }

    /// Snippets saved before they went through `ingest` have no blob, so they paste only their first 500 characters
    /// and are left out of backups. This gives each one a blob from the text it still has and seals its preview.
    /// Idempotent. Clips that hold a secret are left alone: their stored text is a mask.
    @discardableResult
    func giveSnippetsABlob() async throws -> Int {
        let textRaw = ClipboardType.text.rawValue
        var changed = 0
        try await forEachClip(matching: FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned && $0.blob == nil && $0.typeRaw == textRaw }
        )) { item in
            guard item.sensitivityRaw == nil else { return }
            let text = item.displayPreviewText
            guard !text.isEmpty else { return }
            let payload = Data(text.utf8)
            let envelope = try encryption.encrypt(
                payload, associatedData: BlobEncryption.associatedData(itemID: item.id, field: .blob)
            )
            let blob = ClipboardBlob(
                encryptedData: envelope.ciphertext, nonceData: envelope.nonce, mimeType: "public.utf8-plain-text"
            )
            blob.aadBound = true
            item.blob = blob
            modelContext.insert(blob)
            if item.previewCiphertext == nil {
                let preview = try encryption.encrypt(
                    payload, associatedData: BlobEncryption.associatedData(itemID: item.id, field: .preview)
                )
                item.previewCiphertext = preview.ciphertext
                item.previewNonce = preview.nonce
                item.previewAADBound = true
                item.previewText = ""
            }
            changed += 1
        }
        return changed
    }
}

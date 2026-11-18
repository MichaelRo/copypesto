// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Replaces the text of a text, code, link or color clip (ADR 0048). The text is sealed and judged as a copy is
    /// (blob and preview bound to the clip's id, a new content hash, the secret scan, the kind and language read
    /// again, a new search vector and signature); what the person did around it stays: title, note, tags, collection,
    /// pin, first copy and place in the history. An edit is not a use, so the clip does not move. One Undo takes it
    /// back, and sync sends it as a change of the same clip. Rules that rewrite a copy are not applied: the person
    /// typed this. A secret is edited only once it is shown; that is the caller's rule.
    @discardableResult
    func updateText(id: UUID, text: String) throws -> TextEditOutcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else { return .missing }
        let editable = TextEditOutcome.isEditable(type: item.type, analysisPending: item.analysisPending)
        guard item.blob != nil, editable else { return .notText }
        let payload = Data(text.utf8)
        let plainHash = payload.sha256Hex
        let key = try? encryption.loadOrCreateKey()
        let forms = ContentHash.candidates(for: plainHash, key: key)
        if forms.contains(item.contentHash) { return .unchanged }
        var twin = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { forms.contains($0.contentHash) && $0.id != id }
        )
        twin.fetchLimit = 1
        if let other = try modelContext.fetch(twin).first { return .sameAsAnother(other.id) }
        let classified = ContentClassifier.classify(text: text)
        let mimeType = classified.type == .url && item.blob?.mimeType == "public.url"
            ? "public.url" : "public.utf8-plain-text"
        if ClipSizePolicy.isTooLarge(byteCount: payload.count, typeIdentifier: mimeType) {
            throw ClipSizePolicy.TooLarge(message: ClipSizePolicy.message(
                byteCount: payload.count, typeIdentifier: mimeType
            ))
        }
        let before = ClipSnapshot(item: item, linkPreviewFile: linkPreviews.sealedFile(for: id))
        let wasLink = item.type == .url
        do {
            try sealText(payload, mimeType: mimeType, into: item)
            try applyEditedText(text, classified: classified, to: item)
            item.contentHash = ContentHash.stored(plainHash, key: key)
            if wasLink { forgetLinkPreview(of: item) }
            PreviewTextCache.shared.clear()
            try saveOrRollback()
        } catch {
            modelContext.rollback()
            throw error
        }
        if wasLink { linkPreviews.delete(ids: [id]) }
        similarity.remove(id)
        recordReplacement(of: item, before: before, kind: .text)
        lastItemStore.clear(ifItemID: id)
        mirrorIfNewest(item)
        startEmbedding(for: item, text: text)
        noteSignature(of: item, text: text)
        return .saved
    }
}

extension StorageService {
    /// Seals `payload` as the clip's blob under its own id, dropping any rich text from the copy it replaces.
    func sealText(_ payload: Data, mimeType: String, into item: ClipboardItem) throws {
        let envelope = try encryption.encrypt(
            payload, associatedData: BlobEncryption.associatedData(itemID: item.id, field: .blob)
        )
        let blob = item.blob ?? ClipboardBlob(
            encryptedData: envelope.ciphertext, nonceData: envelope.nonce, mimeType: mimeType
        )
        blob.encryptedData = envelope.ciphertext
        blob.nonceData = envelope.nonce
        blob.mimeType = mimeType
        blob.encryptedRichData = nil
        blob.richNonceData = nil
        blob.aadBound = true
        if item.blob == nil {
            item.blob = blob
            modelContext.insert(blob)
        }
    }

    /// A kept password-manager copy stays hidden whatever it is changed to (ADR 0004); anything else is scanned again,
    /// so a secret added is masked and a secret removed is shown.
    private func applyEditedText(
        _ text: String, classified: ContentClassifier.Result, to item: ClipboardItem
    ) throws {
        let keepsCredential = item.sensitivityRaw == SensitivityCategory.credential.rawValue
        item.typeRaw = classified.type.rawValue
        item.detectedLanguage = classified.type == .code || classified.type == .text
            ? classified.detectedLanguage : nil
        item.byteSize = text.utf8.count
        item.textLength = classified.type == .text || classified.type == .code ? text.count : 0
        item.embeddingData = nil
        item.updateMetadata { $0.signature = nil }
        if classified.type == .url, !item.isNSFW, NSFWURLDetector.isExplicit(urlString: text) { item.isNSFW = true }
        if keepsCredential { return }
        let sensitivity = SensitiveContentDetector.detect(in: text)
        item.sensitivityRaw = sensitivity?.category.rawValue
        item.sensitivityMaskedPreview = sensitivity?.maskedPreview
        let preview = sensitivity?.maskedPreview ?? String(text.prefix(500))
        let sealed = try storedPreview(
            for: item.id, clipType: classified.type, sensitivity: sensitivity, preview: preview
        )
        item.previewText = sealed.plain
        item.previewCiphertext = sealed.envelope?.ciphertext
        item.previewNonce = sealed.envelope?.nonce
        item.previewAADBound = sealed.envelope != nil
    }

    private func forgetLinkPreview(of item: ClipboardItem) {
        item.ogImageThumbnail = nil
        item.updateMetadata {
            $0.ogTitle = nil
            $0.ogSiteName = nil
            $0.linkPreviewFetched = nil
        }
    }

    func mirrorIfNewest(_ item: ClipboardItem) {
        var newest = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        newest.fetchLimit = 1
        guard (try? modelContext.fetch(newest).first)?.id == item.id else { return }
        mirrorToLastItemFile(item)
    }
}

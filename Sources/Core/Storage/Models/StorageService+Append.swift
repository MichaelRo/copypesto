// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Appends `capture.payloadString` to the most recent text/code item instead of
    /// creating a new entry. Called by the capture handler when a double-⌘C is detected.
    /// Falls back to normal `ingest(_:)` when no suitable target exists.
    func appendToLatest(_ capture: PasteboardCapture) async throws {
        // A concealed copy (a password manager's) and a hidden clip are never merged into something visible.
        guard !capture.isConcealed, let appendString = capture.payloadString, !appendString.isEmpty else {
            try await ingest(capture)
            return
        }
        guard let plan = try appendPlan(for: appendString) else {
            try await ingest(capture)
            return
        }
        try appendText(appendString, plan: plan, capture: capture)
        try dropDoubleCopyEcho(plan.echoID)
    }
}

extension StorageService {
    /// How long after a clip is stored a double ⌘C may still treat it as the echo of its own first press.
    static let doubleCopyEchoWindow: TimeInterval = 2

    struct AppendPlan {
        let target: ClipboardItem
        let blob: ClipboardBlob
        let existingText: String
        /// The clip made by the first press, to drop once its text is merged into `target`.
        let echoID: UUID?
    }

    /// The watcher polls every 200 ms, so the first press of a double ⌘C has usually been stored as a clip of its
    /// own by the time the second arrives. That clip is the echo of the copy, not "the last clip": the text is
    /// appended to the clip before it and the echo is dropped (never a clip that was only re-dated).
    func appendPlan(for appendString: String) throws -> AppendPlan? {
        let textRaw = ClipboardType.text.rawValue
        let codeRaw = ClipboardType.code.rawValue
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.typeRaw == textRaw || $0.typeRaw == codeRaw },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 2
        let latest = try modelContext.fetch(descriptor)
        guard let first = latest.first, first.sensitivityRaw == nil, let blob = first.blob,
              let text = decryptedText(of: blob) else { return nil }

        let trimmedNew = appendString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let echo = lastInsertedClip, echo.id == first.id,
           clock().timeIntervalSince(echo.at) < Self.doubleCopyEchoWindow,
           text.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedNew,
           latest.count > 1, latest[1].sensitivityRaw == nil, let previousBlob = latest[1].blob,
           let previousText = decryptedText(of: previousBlob)
        {
            return AppendPlan(target: latest[1], blob: previousBlob, existingText: previousText, echoID: first.id)
        }
        return AppendPlan(target: first, blob: blob, existingText: text, echoID: nil)
    }

    func appendText(_ appendString: String, plan: AppendPlan, capture: PasteboardCapture) throws {
        // If the new content is identical to the existing text, just pop the timestamp.
        // This handles the user copying the same item twice quickly (double-⌘C detected)
        // without accumulating "bla\nbla\nbla" duplicates.
        let target = plan.target
        let trimmedNew = appendString.trimmingCharacters(in: .whitespacesAndNewlines)
        if plan.existingText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedNew {
            target.timestamp = capture.timestamp
            try saveOrRollback()
            return
        }

        // A copy of whole lines already ends in a line break; adding another would put a blank line between the parts.
        let separator = plan.existingText.hasSuffix("\n") ? "" : "\n"
        let combined = plan.existingText + separator + appendString
        let textType = capture.typeIdentifier
        if ClipSizePolicy.isTooLarge(byteCount: combined.utf8.count, typeIdentifier: textType) {
            throw ClipSizePolicy.TooLarge(message: ClipSizePolicy.message(
                byteCount: combined.utf8.count, typeIdentifier: textType
            ))
        }
        do {
            let newEnvelope = try encryption.encrypt(
                Data(combined.utf8), associatedData: BlobEncryption.associatedData(itemID: target.id, field: .blob)
            )
            plan.blob.encryptedData = newEnvelope.ciphertext
            plan.blob.nonceData = newEnvelope.nonce
            plan.blob.encryptedRichData = nil
            plan.blob.richNonceData = nil
            plan.blob.aadBound = true
            try applyPreview(of: combined, appended: appendString, to: target)
            target.contentHash = ContentHash.stored(
                Data(combined.utf8).sha256Hex,
                key: try? encryption.loadOrCreateKey()
            )
            target.timestamp = capture.timestamp
            try saveOrRollback()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func dropDoubleCopyEcho(_ id: UUID?) throws {
        guard let id else { return }
        _ = try deleteItems(ids: [id], reason: .merged)
        lastInsertedClip = nil
    }

    func decryptedText(of blob: ClipboardBlob) -> String? {
        let envelope = BlobEncryption.EncryptedEnvelope(ciphertext: blob.encryptedData, nonce: blob.nonceData)
        guard let data = try? encryption.decrypt(envelope, associatedData: blob.associatedData) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Same policy as ingest: text that would be masked on its own stays masked once merged (the detector only
    /// recognises a secret that is the whole text, so the appended part is checked separately), and an item that
    /// was already sensitive stays so even when the text appended to it looks harmless.
    private func applyPreview(of combined: String, appended: String, to target: ClipboardItem) throws {
        target.textLength = combined.count
        let detected = SensitiveContentDetector.detect(in: combined) ?? SensitiveContentDetector.detect(in: appended)
        if let detected {
            target.sensitivityRaw = detected.category.rawValue
            target.sensitivityMaskedPreview = detected.maskedPreview
            target.previewText = detected.maskedPreview
            target.previewCiphertext = nil
            target.previewNonce = nil
            target.previewAADBound = false
        }
        if detected != nil || target.sensitivityRaw != nil {
            target.embeddingData = nil
            lastItemStore.clear(ifItemID: target.id)
            return
        }
        let newPreview = String(combined.prefix(500))
        // Mirror the ingest-path policy: re-encrypt the preview so the appended text
        // doesn't leak to CloudKit as plaintext.
        if let previewData = newPreview.data(using: .utf8) {
            let previewEnvelope = try sealPreview(previewData, itemID: target.id)
            target.previewText = ""
            target.previewCiphertext = previewEnvelope.ciphertext
            target.previewNonce = previewEnvelope.nonce
            target.previewAADBound = true
        } else {
            target.previewText = newPreview
            target.previewCiphertext = nil
            target.previewNonce = nil
            target.previewAADBound = false
        }
    }
}

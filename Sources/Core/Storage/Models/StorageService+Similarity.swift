// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

public extension StorageService {
    private static let similarityLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "Similarity")

    /// How many clips look like `id`, itself included, once three or more do (a family worth a snippet).
    static let minimumFamilySize = 3

    /// Signs a new clip after its card is on the shelf. Everything about it stays on the Mac: the signature is sealed
    /// with the clip's metadata, and only the in-memory index reads it back (ADR 0017).
    func noteSignature(of item: ClipboardItem, text: String) {
        guard TextSignature.isEligible(
            isTextual: item.type == .text || item.type == .code,
            isSensitive: item.sensitivityRaw != nil,
            expires: item.expiresAt != nil,
            length: text.count
        ), let signature = TextSignature.make(from: text) else { return }
        item.updateMetadata { $0.signature = signature.values }
        do {
            try saveOrRollback()
            similarity.insert(signature, for: item.id)
        } catch {
            Self.similarityLogger.error("could not store a signature: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The other clips that look like `id` (at least `threshold` alike), most alike first.
    func lookalikes(of id: UUID, threshold: Double = 0.5) -> [SimilarityIndex.Match] {
        guard let signature = signature(of: id) else { return [] }
        return similarity.matches(for: signature, threshold: threshold, excluding: id)
    }

    /// Loads the signatures already stored into the index, a page at a time. Run at launch and at unlock.
    func loadSimilarityIndex() async throws {
        similarity.removeAll()
        try await forEachClip(matching: FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.metadataCiphertext != nil && $0.sensitivityRaw == nil }
        )) { item in
            guard let values = item.metadata.signature, values.count == TextSignature.width else { return }
            similarity.insert(TextSignature(values: values), for: item.id)
        }
    }

    /// Signs up to `limit` eligible clips that have none, newest first, and returns how many were left to do. The app
    /// calls it in small steps while the Mac is idle, so a long history is indexed without anyone noticing.
    func signMissingClips(limit: Int) throws -> Int {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate {
                $0.sensitivityRaw == nil && $0.expiresAt == nil && !$0.analysisPending && $0.byteSize <= 8000
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 8
        var signed = 0
        var remaining = 0
        for item in try modelContext.fetch(descriptor) where item.type == .text || item.type == .code {
            guard item.metadata.signature == nil, !item.metadataIsUnreadable else { continue }
            guard signed < limit else {
                remaining += 1
                continue
            }
            guard let data = item.blob?.decryptedData(),
                  let text = String(data: data, encoding: .utf8) else { continue }
            guard TextSignature.isEligible(isTextual: true, isSensitive: false, expires: false, length: text.count),
                  let signature = TextSignature.make(from: text) else { continue }
            item.updateMetadata { $0.signature = signature.values }
            similarity.insert(signature, for: item.id)
            signed += 1
        }
        try saveOrRollback()
        return remaining
    }

    /// The history locked: nothing derived from clips stays in memory.
    func dropSimilarityIndex() {
        similarity.removeAll()
    }

    private func signature(of id: UUID) -> TextSignature? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let values = try? modelContext.fetch(descriptor).first?.metadata.signature,
              values.count == TextSignature.width else { return nil }
        return TextSignature(values: values)
    }
}

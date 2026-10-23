// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Re-embeds all text/code items that lack an embedding. Returns the count of newly indexed items.
    func rebuildSemanticIndex() async throws -> Int {
        let textRaw = ClipboardType.text.rawValue
        let codeRaw = ClipboardType.code.rawValue
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate {
                ($0.typeRaw == textRaw || $0.typeRaw == codeRaw) && $0.sensitivityRaw == nil
            }
        )
        let all = try modelContext.fetch(descriptor)
        let candidates = all.filter { $0.embeddingData == nil && $0.displayPreviewText.count > 8 }
        var indexed = 0
        for item in candidates {
            guard let data = await embedder.embed(text: item.displayPreviewText) else { continue }
            item.embeddingData = data
            indexed += 1
        }
        if indexed > 0 { try saveOrRollback() }
        return indexed
    }

    /// Re-runs `ContentClassifier` over existing text/code items so improvements to the
    /// classifier (e.g. fewer prose-as-code false positives) apply retroactively. Only swaps
    /// between `.text` and `.code` and refreshes `detectedLanguage`; never reclassifies into
    /// url/color/image so card rendering isn't disturbed. Returns the number of items changed.
    func reclassifyContentTypes() async throws -> Int {
        let textRaw = ClipboardType.text.rawValue
        let codeRaw = ClipboardType.code.rawValue
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.typeRaw == textRaw || $0.typeRaw == codeRaw }
        )
        var changed = 0
        try await forEachClip(matching: descriptor) { item in
            guard let blob = item.blob,
                  let data = blob.decryptedData(),
                  let text = String(data: data, encoding: .utf8) else { return }
            let result = ContentClassifier.classify(text: text)
            let newType: ClipboardType = (result.type == .code) ? .code : .text
            let newLang: String? = (result.type == .code || result.type == .text) ? result.detectedLanguage : nil
            if item.typeRaw != newType.rawValue || item.detectedLanguage != newLang {
                item.typeRaw = newType.rawValue
                item.detectedLanguage = newLang
                changed += 1
            }
        }
        return changed
    }

    /// Re-screens existing image and link items. Called when the user switches the sensitive filter mode so
    /// previously captured clips get flagged retroactively. Only ever sets `isNSFW = true`. Returns the total count
    /// of sensitive clips in history after the scan.
    func rescanNSFWImages() async throws -> Int {
        let imageRaw = ClipboardType.image.rawValue
        let urlRaw = ClipboardType.url.rawValue
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { ($0.typeRaw == imageRaw || $0.typeRaw == urlRaw) && $0.isNSFW == false }
        )
        let items = try modelContext.fetch(descriptor)
        var newlyFlagged = 0
        for item in items {
            if item.typeRaw == imageRaw {
                guard let blob = item.blob, let data = blob.decryptedData() else { continue }
                if await imageScreener.isSensitive(imageData: data) {
                    item.isNSFW = true
                    newlyFlagged += 1
                }
            } else if item.typeRaw == urlRaw {
                let urlText = item.blob?.decryptedText() ?? item.displayPreviewText
                if NSFWURLDetector.isExplicit(urlString: urlText) {
                    item.isNSFW = true
                    newlyFlagged += 1
                }
            }
        }
        if newlyFlagged > 0 { try saveOrRollback() }
        let totalDescriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.isNSFW == true })
        return try modelContext.fetchCount(totalDescriptor)
    }
}

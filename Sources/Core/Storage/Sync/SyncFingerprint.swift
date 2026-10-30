// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

extension ClipboardItem {
    /// What a sync record would say about this clip. Anything not in here (embeddings, signatures, pop-to-top,
    /// paste days, hotkey slots, per-Mac flags) is this Mac's own business and stamps nothing. Whether the clip was
    /// judged and what it was judged to be are in, so finishing the judgment is itself a change.
    func syncFingerprintValue() -> String {
        let metadata = metadata
        let parts: [String] = [
            id.uuidString, contentHash, typeRaw, String(analysisPending), sensitivityRaw ?? "",
            String(isPinned), collectionID?.uuidString ?? "", expiresAt.map { String($0.timeIntervalSince1970) } ?? "",
            metadata.customTitle ?? "", metadata.userNote ?? "", metadata.tags.joined(separator: "\u{1F}"),
            metadata.customSymbolName ?? "", metadata.collectionOrder.map(String.init) ?? ""
        ]
        return Data(SHA256.hash(data: Data(parts.joined(separator: "\u{1E}").utf8))).hexString
    }
}

extension Pinboard {
    func syncFingerprintValue() -> String {
        let parts: [String] = [
            id.uuidString, name, symbolName, colorHex, String(sortOrder), String(isSmart),
            smartPredicateData.map { Data(SHA256.hash(data: $0)).hexString } ?? "", String(schemaVersion),
            triggerBundleID ?? ""
        ]
        return Data(SHA256.hash(data: Data(parts.joined(separator: "\u{1E}").utf8))).hexString
    }
}

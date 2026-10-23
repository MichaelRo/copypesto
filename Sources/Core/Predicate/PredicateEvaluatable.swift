// SPDX-License-Identifier: MIT
import Foundation

/// Abstract interface used by `PredicateRuleSet.matches` so both production
/// `ClipboardItem` models and lightweight test stubs can be filtered without
/// importing SwiftData into Core tests.
public protocol PredicateEvaluatable {
    var typeRaw: String { get }
    var isPinned: Bool { get }
    /// True when the clip arrived from another device (Universal Clipboard).
    var isRemote: Bool { get }
    var sourceBundleID: String? { get }
    var sourceAppName: String? { get }
    /// Stored preview field. For `ClipboardItem` this is empty for text/code items
    /// post-ADR 0002. Predicate evaluation reads `displayPreviewText` instead.
    var previewText: String { get }
    /// Plaintext preview used by smart-collection rules and content-shape detection.
    /// Defaults to `previewText` for protocol conformers that don't override.
    var displayPreviewText: String { get }
    var detectedLanguage: String? { get }
    var sensitivityRaw: String? { get }
    var tags: [String] { get }
    var timestamp: Date { get }
    var mimeType: String? { get }
}

public extension PredicateEvaluatable {
    var displayPreviewText: String {
        previewText
    }

    var isRemote: Bool {
        false
    }
}

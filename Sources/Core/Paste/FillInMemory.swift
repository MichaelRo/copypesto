// SPDX-License-Identifier: MIT
import Foundation

/// What a snippet remembers of the last prompt: a value per field, sealed with the clip's metadata (ADR 0017). A value
/// that looks like a secret is never kept, nor is one too long to be a name or a reference.
public enum FillInMemory {
    public static let maxValueLength = 500

    public static func remembered(from fills: SnippetFills, fields: [SnippetField]) -> [String: String] {
        var memory: [String: String] = [:]
        for field in fields {
            switch field.kind {
            case .optional:
                memory[field.label] = fills.included.contains(field.label) ? "1" : "0"
            case .text, .choice:
                guard let value = fills.values[field.label], isKeepable(value) else { continue }
                memory[field.label] = value
            }
        }
        return memory
    }

    private static func isKeepable(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxValueLength && SensitiveContentDetector
            .detect(in: trimmed) == nil
    }
}

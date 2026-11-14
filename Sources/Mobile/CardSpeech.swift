// SPDX-License-Identifier: MIT
import Foundation

enum CardSpeech {
    static func label(kind: String, summary: String, source: String?, age: String, isPinned: Bool) -> String {
        var parts = [kind, summary]
        if let source, !source.isEmpty { parts.append(source) }
        parts.append(age)
        if isPinned { parts.append(String(localized: "Pinned")) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

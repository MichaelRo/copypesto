// SPDX-License-Identifier: MIT
import Foundation

/// The edit form's text before it is saved: an empty title or note clears it, and tags are typed comma-separated.
struct ClipDetailsDraft: Equatable {
    var title: String
    var note: String
    var tags: String

    init(title: String?, note: String?, tags: [String]) {
        self.title = title ?? ""
        self.note = note ?? ""
        self.tags = tags.joined(separator: ", ")
    }

    var cleanTitle: String? {
        Self.clean(title)
    }

    var cleanNote: String? {
        Self.clean(note)
    }

    var cleanTags: [String] {
        var seen = Set<String>()
        return tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

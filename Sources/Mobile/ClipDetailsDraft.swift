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

    enum Field: CaseIterable {
        case title, note, tags
    }

    /// The fields the person changed since `baseline`, the values this form last agreed on with the stored clip.
    func touched(since baseline: ClipDetailsDraft) -> Set<Field> {
        Set(Field.allCases.filter { clean($0) != baseline.clean($0) })
    }

    /// The stored clip changed under the open form (a sync, an edit on another device): a field the person has not
    /// touched and is not typing in shows the new value; a touched one keeps what was typed.
    mutating func reconcile(stored: ClipDetailsDraft, baseline: inout ClipDetailsDraft, editing: Field?) {
        for field in Field.allCases where stored.clean(field) != baseline.clean(field) {
            guard field != editing, clean(field) == baseline.clean(field) else { continue }
            set(field, to: stored)
            baseline.set(field, to: stored)
        }
    }

    /// What the form agrees on with the stored clip after saving `fields` from `saved`.
    mutating func didSave(_ fields: Set<Field>, from saved: ClipDetailsDraft) {
        for field in fields { set(field, to: saved) }
    }

    private func clean(_ field: Field) -> String? {
        switch field {
        case .title: cleanTitle
        case .note: cleanNote
        case .tags: cleanTags.isEmpty ? nil : cleanTags.joined(separator: ",")
        }
    }

    private mutating func set(_ field: Field, to other: ClipDetailsDraft) {
        switch field {
        case .title: title = other.title
        case .note: note = other.note
        case .tags: tags = other.tags
        }
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

    func differs(title: String?, note: String?, tags: [String]) -> Bool {
        cleanTitle != Self.clean(title ?? "") || cleanNote != Self.clean(note ?? "") || cleanTags != tags
    }

    private static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

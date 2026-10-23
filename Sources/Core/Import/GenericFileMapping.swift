// SPDX-License-Identifier: MIT

/// What one clip is in a text file.
public enum TextSeparator: String, CaseIterable, Sendable {
    case blankLine, line, dashes
}

/// Which parts of a `GenericFile` become clips. A column that is not chosen is never read.
public struct GenericFileMapping: Sendable, Equatable {
    public var textColumn: Int
    public var dateColumn: Int?
    public var pinnedColumn: Int?
    public var separator: TextSeparator

    private static let textNames = ["content", "text", "clip", "clipping", "value", "body", "string", "data", "item"]
    private static let dateNames = ["copied", "date", "created", "time", "timestamp", "when", "added"]
    private static let pinnedNames = ["pinned", "pin", "favorite", "favourite", "starred", "fav"]

    /// The columns picked by their names, whatever their case or position; the first column is the text when none has a
    /// recognizable name, and the date and pin columns are then left unread.
    public static func detected(for file: GenericFile) -> GenericFileMapping {
        let names = file.columns.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        func index(of candidates: [String]) -> Int? {
            for candidate in candidates {
                if let found = names.firstIndex(where: { $0 == candidate || $0.contains(candidate) }) { return found }
            }
            return nil
        }
        return GenericFileMapping(
            textColumn: index(of: textNames) ?? 0,
            dateColumn: index(of: dateNames),
            pinnedColumn: index(of: pinnedNames),
            separator: .blankLine
        )
    }
}

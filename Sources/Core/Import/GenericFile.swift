// SPDX-License-Identifier: MIT

/// A file of clips from an app Pesto has no reader for, read into rows (CSV, JSON) or text, before the person says
/// which
/// column is the text (`GenericFileMapping`). Nothing is imported from it until they confirm.
public struct GenericFile: Sendable, Equatable {
    public enum Format: Sendable, Equatable {
        case csv, json, text
    }

    public let format: Format
    /// The header of a CSV, or the keys of a JSON list of objects; empty for text.
    public let columns: [String]
    /// One array per row, as long as `columns`; empty for text.
    public let rows: [[String]]
    /// The whole text of a text file; empty for the other formats.
    public let text: String
}

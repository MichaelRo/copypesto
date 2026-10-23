// SPDX-License-Identifier: MIT
import Foundation

/// What a snippet's row in Settings says: a title and a body that does not repeat it.
public struct SnippetRowText: Equatable, Sendable {
    public static let titleLimit = 48

    public let title: String
    public let body: String

    public init(preview: String, customTitle: String?) {
        if let customTitle {
            title = customTitle
            body = preview
            return
        }
        let lines = preview.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        guard let first = lines.first else {
            title = ""
            body = preview
            return
        }
        title = String(first.prefix(Self.titleLimit))
        if first.count <= Self.titleLimit {
            body = lines.dropFirst().joined(separator: "\n")
        } else {
            body = preview
        }
    }
}

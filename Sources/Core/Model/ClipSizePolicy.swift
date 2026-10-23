// SPDX-License-Identifier: MIT
import Foundation
import UniformTypeIdentifiers

/// How much of one copy Pesto will keep. Ingest costs about 115 ms and 10 MB of memory per megabyte of text
/// (measured: 50 MB of text took 5.8 s and peaked at 823 MB), so a copy past the limit is refused, and the person is
/// told.
public enum ClipSizePolicy {
    static let megabyte = 1_048_576
    public static let maxTextBytes = 10 * megabyte
    public static let maxOtherBytes = 100 * megabyte

    public struct TooLarge: Error, Sendable {
        public let message: String

        public init(message: String) {
            self.message = message
        }
    }

    public static func limit(forTypeIdentifier typeIdentifier: String) -> Int {
        isTextLike(typeIdentifier) ? maxTextBytes : maxOtherBytes
    }

    public static func isTooLarge(byteCount: Int, typeIdentifier: String) -> Bool {
        byteCount > limit(forTypeIdentifier: typeIdentifier)
    }

    public static func message(byteCount: Int, typeIdentifier: String) -> String {
        let size = Int((Double(byteCount) / Double(megabyte)).rounded())
        let limit = limit(forTypeIdentifier: typeIdentifier) / megabyte
        let kind = isTextLike(typeIdentifier) ? "text" : "pictures and files"
        return "The last copy is \(size) MB, over the \(limit) MB Pesto keeps for \(kind), so it was not saved."
    }

    private static func isTextLike(_ typeIdentifier: String) -> Bool {
        guard let type = UTType(typeIdentifier) else { return false }
        return type.conforms(to: .text) || type.conforms(to: .url)
    }
}

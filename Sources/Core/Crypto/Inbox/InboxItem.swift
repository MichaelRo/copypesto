// SPDX-License-Identifier: MIT
import Foundation

/// One thing shared to Pesto, as it is sealed into the inbox: text (a link is its text) or a picture's bytes.
public struct InboxItem: Equatable, Sendable {
    public let typeIdentifier: String
    public let payload: Data
    public let createdAt: Date

    public init(typeIdentifier: String, payload: Data, createdAt: Date) {
        self.typeIdentifier = typeIdentifier
        self.payload = payload
        self.createdAt = createdAt
    }

    public static func text(_ text: String, at date: Date = .now) -> InboxItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return InboxItem(typeIdentifier: InboxPolicy.textTypeIdentifier, payload: Data(text.utf8), createdAt: date)
    }

    public static func link(_ url: URL, at date: Date = .now) -> InboxItem? {
        guard url.scheme != nil, !url.isFileURL else { return nil }
        return text(url.absoluteString, at: date)
    }

    public var text: String? {
        typeIdentifier == InboxPolicy.textTypeIdentifier ? String(data: payload, encoding: .utf8) : nil
    }

    /// The item as accepted on either side: a known type, inside its limit, and text that is UTF-8 and not blank.
    public func validated() throws -> InboxItem {
        guard InboxPolicy.accepts(typeIdentifier: typeIdentifier), !payload.isEmpty else {
            throw InboxError.unsupported
        }
        guard payload.count <= InboxPolicy.limit(forTypeIdentifier: typeIdentifier) else { throw InboxError.tooLarge }
        if typeIdentifier == InboxPolicy.textTypeIdentifier {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InboxError.unsupported
            }
        }
        return self
    }

    /// version, milliseconds since 1970, the type's length and bytes, then the payload.
    func plaintext() throws -> Data {
        let type = Data(typeIdentifier.utf8)
        guard type.count <= InboxPolicy.maxTypeIdentifierBytes else { throw InboxError.unsupported }
        var out = Data([Self.version])
        let millis = UInt64(bitPattern: Int64((createdAt.timeIntervalSince1970 * 1000).rounded()))
        out.append(contentsOf: (0..<8).reversed().map { UInt8(truncatingIfNeeded: millis >> (8 * $0)) })
        out.append(contentsOf: [UInt8(type.count >> 8), UInt8(truncatingIfNeeded: type.count)])
        out.append(type)
        out.append(payload)
        return out
    }

    static func parse(plaintext data: Data) throws -> InboxItem {
        let bytes = Data(data)
        guard bytes.count > 11, bytes[0] == version else { throw InboxError.damaged }
        let millis = Int64(bitPattern: bytes.readBigEndianUInt64(at: 1))
        let typeLength = Int(bytes.readBigEndianUInt16(at: 9))
        let typeEnd = 11 + typeLength
        guard typeLength <= InboxPolicy.maxTypeIdentifierBytes, bytes.count >= typeEnd else {
            throw InboxError.damaged
        }
        guard let type = String(data: bytes.subdata(in: 11..<typeEnd), encoding: .utf8) else {
            throw InboxError.damaged
        }
        return InboxItem(
            typeIdentifier: type, payload: bytes.subdata(in: (11 + typeLength)..<bytes.count),
            createdAt: Date(timeIntervalSince1970: Double(millis) / 1000)
        )
    }

    private static let version: UInt8 = 1
}

private extension Data {
    func readBigEndianUInt64(at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { ($0 << 8) | UInt64(self[offset + $1]) }
    }

    func readBigEndianUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }
}

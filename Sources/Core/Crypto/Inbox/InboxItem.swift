// SPDX-License-Identifier: MIT
import Foundation

/// One thing shared to Pesto, as it is sealed into the inbox: text (a link is its text) or a picture's bytes.
public struct InboxItem: Equatable, Sendable {
    public let typeIdentifier: String
    public let payload: Data
    public let createdAt: Date
    public let sourceImageURL: URL?

    public init(typeIdentifier: String, payload: Data, createdAt: Date, sourceImageURL: URL? = nil) {
        self.typeIdentifier = typeIdentifier
        self.payload = payload
        self.createdAt = createdAt
        self.sourceImageURL = sourceImageURL
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
        if let sourceImageURL {
            guard LinkPreviewEligibility.isEligible(sourceImageURL),
                  sourceImageURL.absoluteString.utf8.count <= Int(UInt16.max) else
            {
                throw InboxError.unsupported
            }
        }
        return self
    }

    /// version, milliseconds since 1970, the type's length and bytes, optional sourceImageURL (v2), then the payload.
    func plaintext() throws -> Data {
        let type = Data(typeIdentifier.utf8)
        guard type.count <= InboxPolicy.maxTypeIdentifierBytes else { throw InboxError.unsupported }
        let formatVersion: UInt8 = sourceImageURL == nil ? Self.version1 : Self.version
        var out = Data([formatVersion])
        let millis = UInt64(bitPattern: Int64((createdAt.timeIntervalSince1970 * 1000).rounded()))
        out.append(contentsOf: (0..<8).reversed().map { UInt8(truncatingIfNeeded: millis >> (8 * $0)) })
        out.append(contentsOf: [UInt8(type.count >> 8), UInt8(truncatingIfNeeded: type.count)])
        out.append(type)
        if let sourceImageURL {
            let urlData = Data(sourceImageURL.absoluteString.utf8)
            guard urlData.count <= Int(UInt16.max) else { throw InboxError.unsupported }
            out.append(contentsOf: [UInt8(urlData.count >> 8), UInt8(truncatingIfNeeded: urlData.count)])
            out.append(urlData)
        }
        out.append(payload)
        return out
    }

    static func parse(plaintext data: Data) throws -> InboxItem {
        let bytes = Data(data)
        guard bytes.count > 11 else { throw InboxError.damaged }
        let formatVersion = bytes[0]
        guard formatVersion == version1 || formatVersion == version else { throw InboxError.damaged }
        let millis = Int64(bitPattern: bytes.readBigEndianUInt64(at: 1))
        let typeLength = Int(bytes.readBigEndianUInt16(at: 9))
        let typeEnd = 11 + typeLength
        guard typeLength <= InboxPolicy.maxTypeIdentifierBytes, bytes.count >= typeEnd else {
            throw InboxError.damaged
        }
        guard let type = String(data: bytes.subdata(in: 11..<typeEnd), encoding: .utf8) else {
            throw InboxError.damaged
        }
        var payloadStart = typeEnd
        var sourceImageURL: URL?
        if formatVersion == version {
            guard bytes.count >= typeEnd + 2 else { throw InboxError.damaged }
            let urlLength = Int(bytes.readBigEndianUInt16(at: typeEnd))
            let urlEnd = typeEnd + 2 + urlLength
            guard urlLength > 0, bytes.count >= urlEnd,
                  let urlString = String(data: bytes.subdata(in: (typeEnd + 2)..<urlEnd), encoding: .utf8),
                  let parsed = URL(string: urlString),
                  LinkPreviewEligibility.isEligible(parsed) else { throw InboxError.damaged }
            sourceImageURL = parsed
            payloadStart = urlEnd
        }
        return InboxItem(
            typeIdentifier: type, payload: bytes.subdata(in: payloadStart..<bytes.count),
            createdAt: Date(timeIntervalSince1970: Double(millis) / 1000),
            sourceImageURL: sourceImageURL
        )
    }

    private static let version1: UInt8 = 1
    private static let version: UInt8 = 2
}

private extension Data {
    func readBigEndianUInt64(at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { ($0 << 8) | UInt64(self[offset + $1]) }
    }

    func readBigEndianUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }
}

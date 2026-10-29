// SPDX-License-Identifier: MIT
import Foundation

/// One thing a Mac says in its log: a clip, an edit, a collection, a deletion, a count, a device or a new key.
/// The metadata is JSON and the payload is the clip's bytes (or empty), both sealed inside a segment.
public struct SyncRecord: Equatable, Sendable {
    public enum Kind: UInt8, Sendable, CaseIterable {
        case item = 1
        case curation
        case collection
        case tombstone
        case pasteCounts
        case enroll
        case rekey
    }

    public var kind: Kind
    public var sequence: UInt64
    public var stamp: SyncStamp
    public var metadata: Data
    public var payload: Data

    public init(kind: Kind, sequence: UInt64, stamp: SyncStamp, metadata: Data, payload: Data = Data()) {
        self.kind = kind
        self.sequence = sequence
        self.stamp = stamp
        self.metadata = metadata
        self.payload = payload
    }

    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    public func decodeMetadata<T: Decodable>(_: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(T.self, from: metadata)
    }

    func serialized() -> Data {
        var out = Data([kind.rawValue])
        out.appendBigEndian(sequence)
        out.appendBigEndian(stamp.wallMillis)
        out.appendBigEndian(stamp.counter)
        let device = Data(stamp.deviceID.utf8.prefix(255))
        out.append(UInt8(device.count))
        out.append(device)
        out.appendBigEndian(UInt32(metadata.count))
        out.append(metadata)
        out.append(payload)
        return out
    }

    static func parse(_ data: Data) throws -> SyncRecord {
        var reader = ByteReader(data)
        guard let rawKind = try? reader.byte(), let kind = Kind(rawValue: rawKind) else {
            throw SyncError.malformed("record kind")
        }
        let sequence = try reader.u64()
        let wall = try reader.u64()
        let counter = try reader.u32()
        let device = try reader.bytes(Int(reader.byte()))
        let metadataLength = try Int(reader.u32())
        let metadata = try reader.bytes(metadataLength)
        let stamp = SyncStamp(
            wallMillis: wall,
            counter: counter,
            deviceID: String(bytes: device, encoding: .utf8) ?? ""
        )
        return SyncRecord(kind: kind, sequence: sequence, stamp: stamp, metadata: metadata, payload: reader.rest())
    }
}

struct ByteReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = Data(data)
        offset = 0
    }

    mutating func byte() throws -> UInt8 {
        try bytes(1)[0]
    }

    mutating func u32() throws -> UInt32 {
        try bytes(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func u64() throws -> UInt64 {
        try bytes(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw SyncError.malformed("truncated") }
        defer { offset += count }
        return data.subdata(in: offset..<offset + count)
    }

    var isAtEnd: Bool {
        offset >= data.count
    }

    func rest() -> Data {
        data.subdata(in: offset..<data.count)
    }
}

extension Data {
    mutating func appendBigEndian(_ value: some FixedWidthInteger) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}

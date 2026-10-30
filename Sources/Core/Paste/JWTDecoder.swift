// SPDX-License-Identifier: MIT
import Foundation

public struct JWTDecoding: Equatable, Sendable {
    public enum Validity: Equatable, Sendable {
        case expired(Date)
        case notYetValid(Date)
        case validUntil(Date)
        case noExpiry
    }

    public let headerJSON: String
    public let payloadJSON: String
    public let algorithm: String?
    public let issuedAt: Date?
    public let notBefore: Date?
    public let expiresAt: Date?

    public init(
        headerJSON: String, payloadJSON: String, algorithm: String?,
        issuedAt: Date?, notBefore: Date?, expiresAt: Date?
    ) {
        self.headerJSON = headerJSON
        self.payloadJSON = payloadJSON
        self.algorithm = algorithm
        self.issuedAt = issuedAt
        self.notBefore = notBefore
        self.expiresAt = expiresAt
    }

    public var hasNoSignature: Bool {
        algorithm?.lowercased() == "none"
    }

    public func validity(at now: Date) -> Validity {
        if let notBefore, notBefore > now { return .notYetValid(notBefore) }
        guard let expiresAt else { return .noExpiry }
        return expiresAt > now ? .validUntil(expiresAt) : .expired(expiresAt)
    }
}

/// Reads a JWT's header and payload. It never looks at the signature and never claims a token is valid (ADR 0020).
public enum JWTDecoder {
    public static let maxInputCharacters = 16 * 1024
    public static let maxPartBytes = 64 * 1024

    public static func decode(_ text: String) -> JWTDecoding? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count <= maxInputCharacters else { return nil }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let header = jsonObject(String(parts[0])),
              let payload = jsonObject(String(parts[1])) else { return nil }
        return JWTDecoding(
            headerJSON: pretty(header),
            payloadJSON: pretty(payload),
            algorithm: header["alg"] as? String,
            issuedAt: date(payload["iat"]),
            notBefore: date(payload["nbf"]),
            expiresAt: date(payload["exp"])
        )
    }

    private static func jsonObject(_ part: String) -> [String: Any]? {
        guard let data = base64URLDecode(part), data.count <= maxPartBytes else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func base64URLDecode(_ part: String) -> Data? {
        var base64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        if base64.contains("=") { return nil }
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func pretty(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return TextTransform.jsonPrettyPrint.apply(to: text)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let seconds = number.doubleValue
        guard seconds.isFinite, abs(seconds) < 1e11 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

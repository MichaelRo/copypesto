// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Decoding a JWT without checking it")
struct JWTDecoderTests {
    private func part(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func token(
        header: String = #"{"alg":"HS256","typ":"JWT"}"#,
        payload: String,
        signature: String = "c2ln"
    )
    -> String {
        "\(part(header)).\(part(payload)).\(signature)"
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("header and payload come back as readable JSON")
    func whenWellFormed_thenPrettyJSON() throws {
        let decoded = try #require(JWTDecoder.decode(token(payload: #"{"sub":"42","name":"Ada"}"#)))
        #expect(decoded.headerJSON.contains("\"alg\" : \"HS256\""))
        #expect(decoded.payloadJSON.contains("\"name\" : \"Ada\""))
        #expect(decoded.payloadJSON.contains("\n"))
        #expect(decoded.algorithm == "HS256")
    }

    @Test("base64url with - and _ and no padding decodes")
    func whenPayloadNeedsUrlAlphabet_thenDecodes() throws {
        let payload = #"{"note":"???>>>~~~"}"#
        let encoded = part(payload)
        #expect(encoded.contains("-") || encoded.contains("_"))
        let decoded = try #require(JWTDecoder.decode("\(part(#"{"alg":"none"}"#)).\(encoded)."))
        #expect(decoded.payloadJSON.contains("???>>>~~~"))
    }

    @Test("exp, iat and nbf become dates")
    func whenTimeClaims_thenDates() throws {
        let decoded = try #require(JWTDecoder
            .decode(token(payload: #"{"iat":1799990000,"nbf":1799990100,"exp":1800003600}"#)))
        #expect(decoded.issuedAt == Date(timeIntervalSince1970: 1_799_990_000))
        #expect(decoded.notBefore == Date(timeIntervalSince1970: 1_799_990_100))
        #expect(decoded.expiresAt == Date(timeIntervalSince1970: 1_800_003_600))
    }

    @Test("a token past its exp is expired, one before it is valid until exp")
    func whenExp_thenValidity() throws {
        let past = try #require(JWTDecoder.decode(token(payload: #"{"exp":1799999000}"#)))
        #expect(past.validity(at: now) == .expired(Date(timeIntervalSince1970: 1_799_999_000)))
        let future = try #require(JWTDecoder.decode(token(payload: #"{"exp":1800007200}"#)))
        #expect(future.validity(at: now) == .validUntil(Date(timeIntervalSince1970: 1_800_007_200)))
    }

    @Test("a token before its nbf is not valid yet")
    func whenNotBeforeInFuture_thenNotYetValid() throws {
        let decoded = try #require(JWTDecoder.decode(token(payload: #"{"nbf":1800000500,"exp":1800007200}"#)))
        #expect(decoded.validity(at: now) == .notYetValid(Date(timeIntervalSince1970: 1_800_000_500)))
    }

    @Test("a token with no exp says so")
    func whenNoExp_thenNoExpiry() throws {
        let decoded = try #require(JWTDecoder.decode(token(payload: #"{"sub":"1"}"#)))
        #expect(decoded.validity(at: now) == .noExpiry)
        #expect(decoded.expiresAt == nil)
    }

    @Test("a time claim that is not a number is ignored")
    func whenExpIsText_thenIgnored() throws {
        let decoded = try #require(JWTDecoder.decode(token(payload: #"{"exp":"tomorrow"}"#)))
        #expect(decoded.expiresAt == nil)
    }

    @Test("alg none is flagged, in any case")
    func whenAlgNone_thenNoSignature() throws {
        let none = try #require(JWTDecoder.decode("\(part(#"{"alg":"None"}"#)).\(part("{}"))."))
        #expect(none.hasNoSignature)
        let signed = try #require(JWTDecoder.decode(token(payload: "{}")))
        #expect(!signed.hasNoSignature)
    }

    @Test("the signature is not part of the result")
    func whenDecoded_thenSignatureAbsent() throws {
        let decoded = try #require(JWTDecoder.decode(token(payload: "{}", signature: "SECRETSIGNATURE")))
        #expect(!decoded.headerJSON.contains("SECRETSIGNATURE"))
        #expect(!decoded.payloadJSON.contains("SECRETSIGNATURE"))
    }

    @Test("surrounding whitespace is ignored")
    func whenPadded_thenDecodes() {
        #expect(JWTDecoder.decode("  \n" + token(payload: "{}") + "\n") != nil)
    }

    @Test("malformed tokens give nothing")
    func whenMalformed_thenNil() {
        #expect(JWTDecoder.decode("") == nil)
        #expect(JWTDecoder.decode("abc") == nil)
        #expect(JWTDecoder.decode("a.b") == nil)
        #expect(JWTDecoder.decode("a.b.c.d") == nil)
        #expect(JWTDecoder.decode("!!!.???.sig") == nil)
        #expect(JWTDecoder.decode("\(part("{}")).\(part("{}"))x.sig") == nil)
    }

    @Test("parts that decode but are not JSON objects give nothing")
    func whenNotJSONObject_thenNil() {
        #expect(JWTDecoder.decode("\(part("hello")).\(part("{}")).sig") == nil)
        #expect(JWTDecoder.decode("\(part("{}")).\(part("[1,2]")).sig") == nil)
        #expect(JWTDecoder.decode("\(part("{}")).\(part("\"text\"")).sig") == nil)
    }

    @Test("input over the bound is refused without being decoded")
    func whenHuge_thenNil() {
        let big = String(repeating: "A", count: JWTDecoder.maxInputCharacters)
        #expect(JWTDecoder.decode("\(part("{}")).\(big).sig") == nil)
    }

    @Test("a part that decodes past the bound is refused")
    func whenPayloadDecodesLarge_thenNil() {
        let blob = String(repeating: "a", count: JWTDecoder.maxPartBytes + 1)
        let payload = "{\"x\":\"\(blob)\"}"
        #expect(JWTDecoder.decode(token(payload: payload)) == nil)
    }
}

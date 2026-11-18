// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The words a decoded token's times are shown in")
struct JWTDecodingTextTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private let locale = Locale(identifier: "en_US")

    @Test("a token with an expiry says how long it is valid, and one without says nothing")
    func whenValidUntil_thenTheSpanIsSaid() {
        let text = JWTDecodingText.validityText(
            .validUntil(now.addingTimeInterval(7200)), now: now, calendar: calendar, locale: locale
        )
        #expect(text == "Valid for 2 hours")
        #expect(JWTDecodingText.validityText(.noExpiry, now: now, calendar: calendar, locale: locale) == nil)
    }

    @Test("an expired token says when, and one not yet valid names the day it starts")
    func whenExpiredOrNotYetValid_thenTheTimeIsSaid() throws {
        let expired = try #require(JWTDecodingText.validityText(
            .expired(now.addingTimeInterval(-3600)), now: now, calendar: calendar, locale: locale
        ))
        #expect(expired.hasPrefix("Expired"))
        let later = now.addingTimeInterval(86_400)
        let notYet = try #require(JWTDecodingText.validityText(
            .notYetValid(later), now: now, calendar: calendar, locale: locale
        ))
        #expect(notYet == "Not valid until " + JWTDecodingText.dateText(later, calendar: calendar, locale: locale))
    }
}

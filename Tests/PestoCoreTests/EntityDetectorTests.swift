// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("EntityDetector")
struct EntityDetectorTests {
    // MARK: - Phone numbers

    @Test("standard US format is detected")
    func phone_usFormat_detected() {
        let entities = EntityDetector.detect(in: "Call me at (555) 234-5678 anytime.")
        #expect(entities.contains(.phoneNumber("(555) 234-5678")))
    }

    @Test("dot-separated phone is detected")
    func phone_dotSeparated_detected() {
        let entities = EntityDetector.detect(in: "555.234.5678")
        #expect(entities.contains { if case .phoneNumber = $0 { true } else { false } })
    }

    @Test("E.164 format with country code is detected")
    func phone_e164_detected() {
        let entities = EntityDetector.detect(in: "+1 555 234 5678")
        #expect(entities.contains { if case .phoneNumber = $0 { true } else { false } })
    }

    @Test("phone action URL strips non-digit characters")
    func phone_actionURL_stripsNonDigits() {
        let entity = EntityDetector.Entity.phoneNumber("(555) 234-5678")
        #expect(entity.actionURL == URL(string: "tel://5552345678"))
    }

    @Test("international phone formats with country codes are detected", arguments: [
        ("+44 20 7946 0958", "tel://+442079460958"),
        ("+49 30 123456", "tel://+4930123456"),
        ("+972 50 123 4567", "tel://+972501234567"),
        ("+33 1 42 68 55 55", "tel://+33142685555")
    ])
    func phone_international_detected(input: String, expectedURL: String) {
        let entities = EntityDetector.detect(in: "Call our office at \(input) for support.")
        let phoneEntity = entities.first { if case .phoneNumber = $0 { true } else { false } }
        #expect(phoneEntity != nil)
        #expect(phoneEntity?.actionURL?.absoluteString == expectedURL)
    }

    @Test("a long digit run is not a phone number just because its last ten digits look like one", arguments: [
        "order 986578788855 shipped",
        "reference 12345678901234567890",
        "1Z5R89390357567127",
        "USPS 9400111206206406260787",
        "FedEx 986578788855"
    ])
    func phone_insideLongDigitRun_notDetected(text: String) {
        #expect(!EntityDetector.detect(in: text).contains { if case .phoneNumber = $0 { true } else { false } })
    }

    @Test("numbers that cannot be dialed in North America are not phones", arguments: [
        "000-000-0000", "123-456-7890", "911-555-0100", "(555) 123-4567", "555.012.3456"
    ])
    func phone_impossibleNanp_notDetected(text: String) {
        #expect(!EntityDetector.detect(in: "Call \(text) now").contains {
            if case .phoneNumber = $0 { true } else { false }
        })
    }

    @Test("a dialable number is found next to punctuation and at the edges of the text", arguments: [
        ("Call:(555) 234-5678", "(555) 234-5678"),
        ("tel:555-234-5678", "555-234-5678"),
        ("555-234-5678.", "555-234-5678"),
        ("5552345678", "5552345678"),
        ("1-555-234-5678 today", "1-555-234-5678")
    ])
    func phone_atEdgesAndPunctuation_detected(text: String, expected: String) {
        #expect(EntityDetector.detect(in: text).contains(.phoneNumber(expected)))
    }

    @Test("a ten-digit tracking number is offered for tracking, not for calling")
    func phone_sameDigitsAsTrackingNumber_onlyTracking() {
        let entities = EntityDetector.detect(in: "DHL waybill 3318810025")
        #expect(entities.contains { if case .trackingNumber = $0 { true } else { false } })
        #expect(!entities.contains { if case .phoneNumber = $0 { true } else { false } })
    }

    @Test("5,000 characters of digits and separators are scanned for phones in well under a frame")
    func phone_adversarialInput_isFast() {
        let text = String(repeating: "1-(5) 2.3 ", count: 500)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = EntityDetector.detect(in: text) }
        #expect(elapsed < .milliseconds(200))
    }

    // MARK: - Email addresses

    @Test("plain email is detected")
    func email_plain_detected() {
        let entities = EntityDetector.detect(in: "Contact me at foo@example.com for details.")
        #expect(entities.contains(.email("foo@example.com")))
    }

    @Test("email with plus tag is detected")
    func email_plusTag_detected() {
        let entities = EntityDetector.detect(in: "foo+bar@sub.example.co.uk")
        #expect(entities.contains { if case .email = $0 { true } else { false } })
    }

    @Test("email action URL uses mailto scheme")
    func email_actionURL_mailto() {
        let entity = EntityDetector.Entity.email("foo@example.com")
        #expect(entity.actionURL == URL(string: "mailto:foo@example.com"))
    }

    // MARK: - Street addresses

    @Test("street address is detected")
    func address_street_detected() {
        let entities = EntityDetector.detect(in: "123 Main St")
        #expect(entities.contains { if case .address = $0 { true } else { false } })
    }

    @Test("address action URL uses Apple Maps scheme")
    func address_actionURL_appleMapsDomain() {
        let entity = EntityDetector.Entity.address("123 Main St")
        #expect(entity.actionURL?.host == "maps.apple.com")
    }

    // MARK: - Coordinates

    @Test("decimal and directional coordinates are detected as Apple Maps actions", arguments: [
        ("Location: 37.7749, -122.4194", 37.7749, -122.4194),
        ("Coordinates: 40.7128° N, 74.0060° W", 40.7128, -74.0060),
        ("Pinned at -33.8688, 151.2093 near Sydney", -33.8688, 151.2093)
    ])
    func coordinates_detected(text: String, expectedLat: Double, expectedLon: Double) throws {
        let entities = EntityDetector.detect(in: text)
        let coord = try #require(entities.compactMap { entity -> (Double, Double)? in
            if case let .coordinates(lat, lon) = entity { (lat, lon) } else { nil }
        }.first)
        #expect(abs(coord.0 - expectedLat) < 0.001)
        #expect(abs(coord.1 - expectedLon) < 0.001)
        let entity = EntityDetector.Entity.coordinates(latitude: coord.0, longitude: coord.1)
        #expect(entity.actionURL?.host == "maps.apple.com")
        #expect(entity.actionLabel == "Open in Maps")
        #expect(entity.symbolName == "location")
    }

    @Test("a semicolon or a space can separate the pair, and degrees, minutes and seconds are converted", arguments: [
        ("37.7749; -122.4194", 37.7749, -122.4194),
        ("37.7749;-122.4194", 37.7749, -122.4194),
        ("37.7749 -122.4194", 37.7749, -122.4194),
        ("at 51.50735 -0.12776 today", 51.50735, -0.12776),
        ("40.7128° N 74.0060° W", 40.7128, -74.0060),
        ("40.7128N, 74.0060W", 40.7128, -74.0060),
        ("40°26'46\"N 79°58'56\"W", 40.446111, -79.982222),
        ("40° 26′ 46″ N, 79° 58′ 56″ W", 40.446111, -79.982222),
        ("33°52'04\"S 151°12'36\"E", -33.867778, 151.21)
    ])
    func coordinates_otherNotations(text: String, expectedLat: Double, expectedLon: Double) throws {
        let coord = try #require(EntityDetector.detect(in: text).compactMap { entity -> (Double, Double)? in
            if case let .coordinates(lat, lon) = entity { (lat, lon) } else { nil }
        }.first)
        #expect(abs(coord.0 - expectedLat) < 0.0001, "\(text): latitude \(coord.0)")
        #expect(abs(coord.1 - expectedLon) < 0.0001, "\(text): longitude \(coord.1)")
    }

    @Test("version numbers, short decimals and impossible pairs are not coordinates", arguments: [
        "version 1.2.3.4", "prices 12.5 13.5", "ratios 1.25 2.50", "1.5; 2", "95.1234 45.1234", "45.1234 190.1234",
        "40°61'46\"N 79°58'56\"W", "40°26'61\"N 79°58'56\"W", "91°26'46\"N 79°58'56\"W", "40°26'46\"N 181°58'56\"W"
    ])
    func coordinates_notThese(text: String) {
        let entities = EntityDetector.detect(in: text)
        #expect(!entities.contains { if case .coordinates = $0 { true } else { false } }, "\(text)")
    }

    @Test("a hostile run of degree signs and digits is scanned in well under a frame")
    func coordinates_adversarialIsFast() {
        let text = String(repeating: "40°26'46\" 79°58' ", count: 30) + String(repeating: "12.34567 ", count: 40)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = EntityDetector.detect(in: text) }
        #expect(elapsed < .milliseconds(50))
    }

    @Test("simple integer lists are not detected as coordinates")
    func coordinates_rejectsSimpleIntegerLists() {
        let entities = EntityDetector.detect(in: "Items 1, 2 were shipped")
        #expect(!entities.contains { if case .coordinates = $0 { true } else { false } })
    }

    // MARK: - Deduplication

    @Test("duplicate phone numbers produce one entity")
    func dedup_samePhone_onlyOnce() {
        let text = "Call (555) 234-5678 or (555) 234-5678"
        let phones = EntityDetector.detect(in: text).filter { if case .phoneNumber = $0 { true } else { false } }
        #expect(phones.count == 1)
    }

    // MARK: - No false positives

    @Test("random numbers are not detected as phones")
    func noFalsePositive_shortNumbers() {
        let entities = EntityDetector.detect(in: "I have 12345 items.")
        let phones = entities.filter { if case .phoneNumber = $0 { true } else { false } }
        #expect(phones.isEmpty)
    }

    @Test("word without @ is not detected as email")
    func noFalsePositive_noAtSign() {
        let entities = EntityDetector.detect(in: "Send to example dot com")
        let emails = entities.filter { if case .email = $0 { true } else { false } }
        #expect(emails.isEmpty)
    }
}

@Suite("EntityDetector: dates, tracking numbers and links")
struct SmartEntityTests {
    @Test("a date and time in text becomes an Add to Calendar action")
    func whenDateWithTime_thenEvent() throws {
        let entities = EntityDetector.detect(in: "Team lunch on 15 March 2027 at 12:30")
        let event = try #require(entities.compactMap { entity -> EntityDetector.EventDetails? in
            if case let .date(details) = entity { details } else { nil }
        }.first)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.start)
        #expect(parts.year == 2027 && parts.month == 3 && parts.day == 15)
        #expect(parts.hour == 12 && parts.minute == 30 && event.hasTime)
        #expect(event.title.contains("Team lunch"))
    }

    @Test("a bare date is an all-day event")
    func whenDateWithoutTime_thenAllDay() throws {
        let entities = EntityDetector.detect(in: "Conference 20 October 2027")
        let event = try #require(entities.compactMap { entity -> EntityDetector.EventDetails? in
            if case let .date(details) = entity { details } else { nil }
        }.first)
        #expect(!event.hasTime)
    }

    @Test("long text is not scanned for dates, so a document does not sprout event actions")
    func whenLongText_thenNoDate() {
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 40)
        let entities = EntityDetector.detect(in: filler + " on 3 May 2027 " + filler)
        #expect(!entities.contains { if case .date = $0 { true } else { false } })
    }

    @Test("carrier tracking numbers are recognised, and each opens that carrier's page", arguments: [
        ("Your parcel 1Z999AA10123456784 shipped", EntityDetector.Carrier.ups, "ups.com"),
        ("USPS 9405803699300124287899", EntityDetector.Carrier.usps, "usps.com"),
        ("Parcel 9400111206206406260787 is on its way", EntityDetector.Carrier.usps, "usps.com"),
        ("USPS 20-digit 03071790000523483741", EntityDetector.Carrier.usps, "usps.com"),
        ("USPS legacy 71969010756003077385", EntityDetector.Carrier.usps, "usps.com"),
        ("FedEx tracking 986578788855", EntityDetector.Carrier.fedex, "fedex.com"),
        ("FedEx Ground 568283610012734", EntityDetector.Carrier.fedex, "fedex.com"),
        ("FedEx Ground 22-digit 9611020987654312345672", EntityDetector.Carrier.fedex, "fedex.com"),
        ("DHL waybill 3318810025", EntityDetector.Carrier.dhl, "dhl.com"),
        ("DHL Express 73891051146", EntityDetector.Carrier.dhl, "dhl.com")
    ])
    func whenTrackingNumber_thenCarrierLink(text: String, carrier: EntityDetector.Carrier, host: String) throws {
        let found = try #require(EntityDetector.detect(in: text).compactMap { entity -> (
            EntityDetector.Carrier,
            String
        )? in
            if case let .trackingNumber(carrier, number) = entity { (carrier, number) } else { nil }
        }.first)
        #expect(found.0 == carrier)
        let url = try #require(EntityDetector.Entity.trackingNumber(found.0, found.1).actionURL)
        #expect(url.host?.hasSuffix(host) == true)
        #expect(url.absoluteString.contains(found.1))
    }

    @Test("a number that fails its carrier's check digit is not offered", arguments: [
        "Parcel 1Z5R89390357567128 shipped",
        "Parcel 9434611206206407667131 shipped",
        "USPS 9400111899223197428490",
        "USPS 03071790000523483742",
        "FedEx 996578788855",
        "FedEx 568283610012732",
        "DHL 3318810010"
    ])
    func whenCheckDigitFails_thenNotTracking(text: String) {
        let entities = EntityDetector.detect(in: text)
        #expect(!entities.contains { if case .trackingNumber = $0 { true } else { false } }, "\(text)")
    }

    @Test("a 20-digit number needs USPS named, a 21-digit run is never tracking, and 20-digit FedEx is not a format")
    func whenOtherLengths_thenNotOffered() {
        func tracking(_ text: String) -> Bool {
            EntityDetector.detect(in: text).contains { if case .trackingNumber = $0 { true } else { false } }
        }
        #expect(!tracking("Reference 03071790000523483741"))
        #expect(tracking("USPS 03071790000523483741"))
        #expect(!tracking("USPS 940011120620640626078"))
        #expect(!tracking("FedEx 96120190598037281023"))
    }

    @Test("a long number embedded in text is still offered once, with spaces around it")
    func whenLongNumber_thenOneOffer() {
        let found = EntityDetector.detect(in: "a 1Z5R89390357567127, b 1Z5R89390357567127.").filter {
            if case .trackingNumber = $0 { true } else { false }
        }
        #expect(found.count == 1)
    }

    @Test("a bare 12-digit number is not called a FedEx parcel without the carrier's name")
    func whenDigitsWithoutCarrier_thenNotTracking() {
        let entities = EntityDetector.detect(in: "Order number 986578788855 was paid")
        #expect(!entities.contains { if case .trackingNumber = $0 { true } else { false } })
    }

    @Test("web links inside text are offered, but email and phone links are not duplicated")
    func whenLinkInText_thenOpenLink() throws {
        let entities = EntityDetector.detect(in: "Docs at https://example.com/guide and mail me@example.com")
        #expect(try entities.contains(.link(#require(URL(string: "https://example.com/guide")))))
        #expect(!entities.contains { if case let .link(url) = $0 { url.scheme == "mailto" } else { false } })
    }

    @Test("every new action has a label and an icon")
    func whenNewEntity_thenPresentable() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let examples: [EntityDetector.Entity] = try [
            .date(.init(title: "x", start: start, hasTime: true)),
            .trackingNumber(.ups, "1Z999AA10123456784"),
            .link(#require(URL(string: "https://example.com")))
        ]
        for entity in examples {
            #expect(!entity.actionLabel.isEmpty && !entity.symbolName.isEmpty)
        }
    }
}

@Suite("Calendar file for a detected date")
struct CalendarFileTests {
    private let stamp = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    @Test("a timed event has UTC start and end an hour later")
    func whenTimed_thenUTCStartAndEnd() {
        let start = Date(timeIntervalSince1970: 1_800_003_600)
        let ics = ICalendarEvent.make(title: "Team lunch", start: start, hasTime: true, uid: "abc", now: stamp)
        let lines = ics.components(separatedBy: "\r\n")

        #expect(lines.contains("BEGIN:VCALENDAR") && lines.contains("END:VCALENDAR"))
        #expect(lines.contains("SUMMARY:Team lunch"))
        #expect(lines.contains("UID:abc@pesto"))
        #expect(lines.contains("DTSTAMP:20270115T080000Z"))
        #expect(lines.contains("DTSTART:20270115T090000Z"))
        #expect(lines.contains("DTEND:20270115T100000Z"))
    }

    @Test("an all-day event uses date values and ends the next day")
    func whenAllDay_thenDateValues() {
        let ics = ICalendarEvent.make(
            title: "Conference", start: stamp, hasTime: false, uid: "abc", now: stamp, calendar: utc
        )
        let lines = ics.components(separatedBy: "\r\n")
        #expect(lines.contains("DTSTART;VALUE=DATE:20270115"))
        #expect(lines.contains("DTEND;VALUE=DATE:20270116"))
    }

    @Test("commas, semicolons, backslashes and line breaks in the title are escaped")
    func whenTitleHasSpecialCharacters_thenEscaped() {
        let ics = ICalendarEvent.make(title: "A, B; C\\D\nE", start: stamp, hasTime: true, uid: "abc", now: stamp)
        #expect(ics.contains("SUMMARY:A\\, B\\; C\\\\D\\nE"))
    }

    @Test("lines end with CRLF as the format requires")
    func whenBuilt_thenCRLF() {
        let ics = ICalendarEvent.make(title: "x", start: stamp, hasTime: true, uid: "abc", now: stamp)
        #expect(ics.hasSuffix("END:VCALENDAR\r\n"))
        #expect(!ics.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }
}

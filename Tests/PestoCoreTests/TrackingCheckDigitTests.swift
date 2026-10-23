// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

/// Every number here is a published test number from https://github.com/jkeen/tracking_number_data (the `test_numbers`
/// of its UPS, USPS, FedEx and DHL definitions, read 2026-10-21), or an invalid one that file lists. None was made by
/// the code under test.
@Suite("Carrier check digits")
struct TrackingCheckDigitTests {
    @Test("UPS: the published valid numbers pass and the published invalid ones fail", arguments: [
        ("1Z5R89390357567127", true), ("1Z879E930346834440", true), ("1Z410E7W0392751591", true),
        ("1Z8V92A70367203024", true), ("1Z999AA10123456784", true),
        ("1Z1111111111111111", false), ("2Z5R89390357567127", false), ("1A5R89390357567127", false),
        ("1Z5R89390357567128", false), ("1Z5R8939035756712X", false)
    ])
    func ups(number: String, valid: Bool) {
        #expect(TrackingCheckDigit.isValidUPS(number) == valid)
    }

    @Test("USPS: 22 and 20 digit numbers by their mod 10 check", arguments: [
        ("9405803699300124287899", true), ("9400111206206406260787", true), ("9434611206206406227577", true),
        ("9400111201080805483016", true), ("9101123456789000000013", true),
        ("03071790000523483741", true), ("71123456789123456787", true),
        ("71969010756003077385", true), ("71969010756003077386", false),
        ("9434611206206407667131", false), ("9101123456789000000014", false), ("03071790000523483742", false)
    ])
    func usps(number: String, valid: Bool) {
        #expect(TrackingCheckDigit.isValidUSPS(number) == valid)
    }

    @Test("FedEx Express (12 digits)", arguments: [
        ("986578788855", true), ("477179081230", true), ("799531274483", true), ("790535312317", true),
        ("996578788855", false)
    ])
    func fedexExpress(number: String, valid: Bool) {
        #expect(TrackingCheckDigit.isValidFedExExpress(number) == valid)
    }

    @Test("FedEx Ground (15 digits)", arguments: [
        ("041441760228964", true), ("568283610012000", true), ("568283610012734", true),
        ("568283610012732", false)
    ])
    func fedexGround(number: String, valid: Bool) {
        #expect(TrackingCheckDigit.isValidFedExGround(number) == valid)
    }

    @Test("DHL Express, 10 and 11 digits", arguments: [
        ("3318810025", true), ("73891051146", true), ("8487135506", true), ("1099255990", true),
        ("3821724944", true), ("3318810010", false), ("3318810034", false)
    ])
    func dhl(number: String, valid: Bool) {
        #expect(TrackingCheckDigit.isValidDHL(number) == valid)
    }

    @Test("a number of the wrong shape or with other characters is never valid")
    func whenWrongShape_thenInvalid() {
        #expect(!TrackingCheckDigit.isValidFedExExpress("98657878885"))
        #expect(!TrackingCheckDigit.isValidFedExGround("56828361001273"))
        #expect(!TrackingCheckDigit.isValidDHL("331881002"))
        #expect(!TrackingCheckDigit.isValidUSPS("9405803699300124287A99"))
        #expect(!TrackingCheckDigit.isValidUPS("1Z"))
        #expect(!TrackingCheckDigit.isValidUSPS(""))
    }
}

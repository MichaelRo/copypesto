// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("What the Format and From chips say")
struct FilterMenuLabelTests {
    @Test("Format reads Any at rest, so it does not repeat the caption above it, and the format once one is chosen")
    func format_namesItsValue() {
        #expect(FilterMenuLabel.format(chosen: nil) == "Any")
        #expect(FilterMenuLabel.format(chosen: "JSON") == "JSON")
    }

    @Test("From reads Any app at rest, then the app, then the first app and how many more")
    func from_namesItsValue() {
        #expect(FilterMenuLabel.from(chosen: []) == "Any app")
        #expect(FilterMenuLabel.from(chosen: ["Safari"]) == "Safari")
        #expect(FilterMenuLabel.from(chosen: ["Safari", "Mail", "Notes"]) == "Safari +2")
    }
}

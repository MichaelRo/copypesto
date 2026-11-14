// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The one line of facts at a card's foot")
struct CardFootLineTests {
    private let phone = CardFootLine.Device(name: "iPhone", symbol: "iphone")

    @Test("a clip from a known app names the app, then its age")
    func whenAppIsKnown_thenItLeads() {
        let line = CardFootLine.make(
            .init(isRemote: false, appName: "Safari", arrivedBySync: true), title: nil, age: "4m ago", device: phone
        )
        #expect(line.texts.first == "Safari \u{00B7} 4m ago")
        #expect(line.symbol == nil)
    }

    @Test("a clip made on this device names the device, never an unknown app")
    func whenCapturedHere_thenTheDeviceLeads() {
        let line = CardFootLine.make(
            .init(isRemote: false, appName: nil, arrivedBySync: false), title: nil, age: "just now", device: phone
        )
        #expect(line.texts.first == "iPhone \u{00B7} just now")
        #expect(line.symbol == "iphone")
        #expect(!line.texts.contains { $0.contains("Unknown") })
    }

    @Test("a Universal Clipboard copy says it came from another device")
    func whenRemote_thenAnotherDevice() {
        let line = CardFootLine.make(
            .init(isRemote: true, appName: "Safari", arrivedBySync: false), title: nil, age: "2m ago", device: phone
        )
        #expect(line.texts.first == "Another device \u{00B7} 2m ago")
    }

    @Test("a synced clip with no app name shows its age alone")
    func whenSyncedWithoutAName_thenAgeAlone() {
        let line = CardFootLine.make(
            .init(isRemote: false, appName: nil, arrivedBySync: true), title: nil, age: "1h ago", device: phone
        )
        #expect(line.texts == ["1h ago"])
        #expect(line.symbol == nil)
    }

    @Test("a title the person gave takes the source's place and is the last thing kept")
    func whenTitled_thenTheTitleLeads() {
        let line = CardFootLine.make(
            .init(appName: "Notes", arrivedBySync: true), title: "Gate code", age: "3m ago", device: phone
        )
        #expect(line.texts == ["Gate code \u{00B7} 3m ago", "Gate code"])
        #expect(line.symbol == nil)
    }
}

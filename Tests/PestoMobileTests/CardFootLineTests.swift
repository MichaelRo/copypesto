// SPDX-License-Identifier: MIT
import Foundation
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

    @Test("the age is read from the grid's clock, so a minute's tick moves it")
    @MainActor
    func whenTheClockTicks_thenTheAgeMoves() {
        let copied = Date(timeIntervalSince1970: 1_800_000_000)
        let item = ClipboardItem(
            timestamp: copied, type: .text, previewText: "", contentHash: "h", byteSize: 1, deviceID: "d",
            sequenceNumber: 1
        )
        let early = CardFootLineView.line(for: item, now: copied.addingTimeInterval(5), device: phone)
        let later = CardFootLineView.line(for: item, now: copied.addingTimeInterval(3 * 60 + 5), device: phone)
        #expect(early.texts.first != later.texts.first)
        #expect(later.texts.first?.contains(CardAge.text(interval: 3 * 60 + 5)) == true)
    }

    @Test("a clip made here says how it came in instead of the device's name", arguments: CaptureMethod.allCases)
    func whenMadeHereWithAMethod_thenTheMethodLeads(method: CaptureMethod) {
        let line = CardFootLine.make(
            .init(isRemote: false, appName: nil, arrivedBySync: false, captureMethod: method), title: nil,
            age: "just now", device: phone
        )
        let words = ["paste": "Pasted", "note": "Note", "share": "Shared", "drop": "Dropped", "shortcut": "Shortcut"]
        #expect(line.texts.first == "\(words[method.rawValue] ?? "?") \u{00B7} just now")
        #expect(line.symbol == "iphone")
    }

    @Test("an app's name still leads for a clip that came with one, whatever its method")
    func whenAnAppIsNamed_thenItStillLeads() {
        let line = CardFootLine.make(
            .init(isRemote: false, appName: "Safari", arrivedBySync: true, captureMethod: nil), title: nil,
            age: "4m ago", device: phone
        )
        #expect(line.texts.first == "Safari \u{00B7} 4m ago")
    }

    @Test("a share drained from the inbox is marked as shared")
    func whenDrainedFromTheInbox_thenTheCaptureIsShared() {
        let capture = InboxDrain.capture(of: InboxItem(
            typeIdentifier: "public.utf8-plain-text", payload: Data("hello".utf8), createdAt: .now
        ))
        #expect(capture.captureMethod == .share)
        #expect(capture.with(timestamp: .distantPast).captureMethod == .share)
    }
}

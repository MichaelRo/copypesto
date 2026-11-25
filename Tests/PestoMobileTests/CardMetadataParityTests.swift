// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Card metadata, animated link GIFs, and new color schemas on iOS")
@MainActor
struct CardMetadataParityTests {
    @Test("whole-string color parsing renders bare hex and CSS Color 4 swatches on iOS")
    func whenWholeColorSchema_thenSummaryAndFactsShowColor() {
        let copied = Date(timeIntervalSince1970: 1_800_000_000)
        for text in ["FF8800", "oklch(0.62 0.19 250)", "cmyk(0%, 100%, 100%, 0%)"] {
            let item = ClipboardItem(
                timestamp: copied, type: .color, previewText: text,
                contentHash: text, byteSize: text.utf8.count, deviceID: "d", sequenceNumber: 1
            )
            let summary = ClipSummary.make(
                item,
                concealment: CardConcealment(screenShareBlur: false, sensitiveBlur: false)
            )
            guard case .swatch = summary.visual else {
                Issue.record("Expected swatch for \(text), got \(summary.visual)")
                return
            }
            let facts = ClipFacts.facts(for: item, collectionName: nil, isShown: true)
            #expect(facts.contains { if case .rgb = $0 { return true }
                return false
            })
        }
    }

    @Test("detail facts surface sourceAppName or peer device name for synced clips")
    func whenSourceAppOrPeerDeviceKnown_thenFactsIncludeOrigin() {
        let copied = Date(timeIntervalSince1970: 1_800_000_000)
        let fromApp = ClipboardItem(
            timestamp: copied, type: .text, sourceAppName: "Xcode", previewText: "let x = 1",
            contentHash: "h1", byteSize: 9, deviceID: "d", sequenceNumber: 1
        )
        fromApp.syncOrigin = "peer-1"
        let appStrings = ClipFacts.factStrings(
            for: fromApp, collectionName: nil, isShown: true, peerDeviceNames: ["peer-1": "Work Mac"]
        )
        #expect(appStrings.first == "Xcode")

        let syncedNoApp = ClipboardItem(
            timestamp: copied, type: .text, sourceAppName: nil, previewText: "hello",
            contentHash: "h2", byteSize: 5, deviceID: "d", sequenceNumber: 2
        )
        syncedNoApp.syncOrigin = "peer-1"
        let peerStrings = ClipFacts.factStrings(
            for: syncedNoApp, collectionName: nil, isShown: true, peerDeviceNames: ["peer-1": "Work Mac"]
        )
        #expect(peerStrings.first == "Work Mac")
    }
}

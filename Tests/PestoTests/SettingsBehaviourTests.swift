// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Appearance settings become layout", .serialized)
    struct SettingsBehaviourTests {
        private func withCardSize(_ raw: String?, _ body: () -> Void) {
            let key = "cardSize"
            let previous = AppDefaults.store.string(forKey: key)
            if let raw { AppDefaults.store.set(raw, forKey: key) } else { AppDefaults.store.removeObject(forKey: key) }
            defer { AppDefaults.store.set(previous, forKey: key) }
            body()
        }

        @Test("each card size has its documented dimensions, growing from compact to large")
        func whenCardSize_thenDimensions() {
            #expect(CardSize.compact.cardCGSize == CGSize(width: 160, height: 140))
            #expect(CardSize.standard.cardCGSize == CGSize(width: 180, height: 160))
            #expect(CardSize.large.cardCGSize == CGSize(width: 200, height: 180))
        }

        @Test("the shelf is as tall as the stored card size needs", arguments: CardSize.allCases)
        func whenSizeStored_thenShelfHeight(size: CardSize) {
            withCardSize(size.rawValue) {
                #expect(BottomShelfPositioning.overlayHeight == ShelfHeight
                    .height(forCardHeight: size.cardCGSize.height))
            }
        }

        @Test("a width set with the slider decides the card and the shelf height, and zero means no custom width")
        func whenWidthStored_thenItDecidesTheDimensions() {
            let defaults = AppDefaults.store
            let previous = defaults.object(forKey: "cardWidth")
            defer { defaults.set(previous, forKey: "cardWidth") }

            defaults.set(150, forKey: "cardWidth")
            #expect(CardSize.dimensions(sizeRaw: "large", customWidth: 150) == CGSize(width: 150, height: 130))
            #expect(BottomShelfPositioning.overlayHeight == ShelfHeight.height(forCardHeight: 130))

            defaults.set(0, forKey: "cardWidth")
            #expect(CardSize.dimensions(sizeRaw: "compact", customWidth: 0) == CardSize.compact.cardCGSize)
            #expect(
                CardSize.dimensions(sizeRaw: nil, customWidth: 5) == CardSize.large.cardCGSize,
                "out of range is ignored"
            )
        }

        @Test("an unset or unknown card size means large")
        func whenSizeMissingOrGarbage_thenLarge() {
            let large = ShelfHeight.height(forCardHeight: CardSize.large.cardCGSize.height)
            withCardSize(nil) { #expect(BottomShelfPositioning.overlayHeight == large) }
            withCardSize("gigantic") { #expect(BottomShelfPositioning.overlayHeight == large) }
        }

        @Test("accent colours parse from six or eight hex digits, with or without a hash")
        func whenHex_thenColour() {
            #expect(Color(hex: "#FF5733") != nil)
            #expect(Color(hex: "FF5733") != nil)
            #expect(Color(hex: "#FF573380") != nil)
        }

        @Test("malformed accent colours are rejected, so the system accent is used instead")
        func whenBadHex_thenNil() {
            for bad in ["", "#", "FFF", "#12345", "GGGGGG", "#1234567"] {
                #expect(Color(hex: bad) == nil, "\(bad)")
            }
        }

        @Test("a colour round-trips through its hex form")
        func whenRoundTripped_thenSame() {
            #expect(Color(hex: "#3366CC")?.toHex() == "3366CC")
            #expect(HSBColor(hex: "#3366CC")?.hexString == "3366CC")
            #expect(HSBColor(hex: "E06C75")?.hexString == "E06C75")
            #expect(HSBColor(hex: "invalid") == nil)
        }
    }

    @Suite("Shortcuts action", .serialized)
    struct PasteFromPestoIntentTests {
        @Test("Paste from Pesto finds an item by its text, instead of always reporting the app as not ready")
        @MainActor
        func whenItemExists_thenIntentReturnsIt() async throws {
            let container = try ModelContainerSetup.makeInMemory().synced
            let state = AppState()
            state.historyContainer = container
            let previous = ScriptingContext.appState
            ScriptingContext.appState = state
            defer { ScriptingContext.appState = previous }
            let context = ModelContext(container)
            let marker = "intent-check-\(UUID().uuidString)"
            let item = ClipboardItem(
                type: .text, previewText: marker, contentHash: marker, byteSize: marker.count, deviceID: "t",
                sequenceNumber: 1
            )
            context.insert(item)
            try context.save()
            defer {
                context.delete(item)
                try? context.save()
            }

            let intent = PasteFromPestoIntent()
            intent.search = marker
            let result = try await intent.perform()

            #expect(result.value == marker)
        }
    }
}

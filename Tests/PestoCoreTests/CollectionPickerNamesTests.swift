// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Collection colors and icons have names VoiceOver can say")
struct CollectionPickerNamesTests {
    @Test("every palette color has a plain name, and a custom one is just Custom")
    func whenPaletteColor_thenNamed() {
        for hex in CollectionPalette.colors {
            let name = CollectionPalette.name(forHex: hex)
            #expect(name != "Custom" && !name.contains(hex), "\(hex) is spoken as \(name)")
        }
        #expect(CollectionPalette.name(forHex: "#007aff") == "Blue")
        #expect(CollectionPalette.name(forHex: "123456") == "Custom")
    }

    @Test("the names are all different, so two swatches never sound alike")
    func whenNamed_thenDistinct() {
        let names = CollectionPalette.colors.map(CollectionPalette.name(forHex:))
        #expect(Set(names).count == names.count)
    }

    @Test("every icon has a word that is not its symbol name, and the words are distinct")
    func whenIcon_thenNamed() {
        for (symbol, name) in CollectionSymbols.choices {
            #expect(!name.isEmpty && name != symbol && !name.contains("."), "\(symbol)")
        }
        let names = CollectionSymbols.choices.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(Set(CollectionSymbols.symbols).count == CollectionSymbols.symbols.count)
        #expect(CollectionSymbols.name(for: "tray.full") == "Tray")
    }
}

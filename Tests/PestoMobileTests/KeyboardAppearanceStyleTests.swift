// SPDX-License-Identifier: MIT
import Testing
import UIKit

@Suite("The keyboard looks like the one the text field asked for")
struct KeyboardAppearanceStyleTests {
    @Test("a field that asks for a dark or light keyboard gets it; default follows the system")
    func whenFieldAsks_thenTheKeyboardFollows() {
        #expect(KeyboardAppearanceStyle.style(for: .dark) == .dark)
        #expect(KeyboardAppearanceStyle.style(for: .light) == .light)
        #expect(KeyboardAppearanceStyle.style(for: .default) == .unspecified)
        #expect(KeyboardAppearanceStyle.style(for: nil) == .unspecified)
    }
}

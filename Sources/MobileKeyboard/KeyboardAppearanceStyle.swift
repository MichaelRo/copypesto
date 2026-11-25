// SPDX-License-Identifier: MIT
import UIKit

/// Apple's keyboard follows the text field's own request (`keyboardAppearance`, a dark keyboard in a dark-themed app
/// while the phone is in Light) and otherwise the system's appearance; Pesto's keys, cards and search page do the same.
enum KeyboardAppearanceStyle {
    static func style(for appearance: UIKeyboardAppearance?) -> UIUserInterfaceStyle {
        switch appearance {
        case .dark: .dark
        case .light: .light
        default: .unspecified
        }
    }
}

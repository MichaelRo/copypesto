// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

/// The switch key iOS asks every keyboard for. It is a UIKit button because only `handleInputModeList(from:with:)`,
/// fed the button's own touches, shows the system's list of keyboards on a long press.
struct GlobeKey: UIViewRepresentable {
    weak var controller: UIInputViewController?

    func makeUIView(context _: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = String(localized: "Next Keyboard")
        if let controller {
            button.addTarget(
                controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                for: .allTouchEvents
            )
        }
        return button
    }

    func updateUIView(_: UIButton, context _: Context) {}
}

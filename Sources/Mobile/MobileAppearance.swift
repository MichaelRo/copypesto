// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The person's Light, Dark or System choice, applied to every window of the app. `preferredColorScheme(nil)` did not
/// reliably hand a window back to the system after Dark (some controls stayed dark), so the choice is set where UIKit
/// keeps it: `overrideUserInterfaceStyle` on each window, which every sheet and menu in it inherits.
enum MobileAppearance {
    static func interfaceStyle(appearance stored: String) -> UIUserInterfaceStyle {
        switch AppearanceMode(rawValue: stored) {
        case .light: .light
        case .dark: .dark
        case .system, nil: .unspecified
        }
    }

    @MainActor
    static func apply(_ style: UIUserInterfaceStyle, to scenes: Set<UIScene>) {
        for case let scene as UIWindowScene in scenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    @MainActor
    static func applyTint(_ tintColor: UIColor, to scenes: Set<UIScene>) {
        for case let scene as UIWindowScene in scenes {
            for window in scene.windows where window.tintColor != tintColor {
                window.tintColor = tintColor
            }
        }
    }
}

/// Applies the appearance at the root of each window: when it appears, when the setting changes and when the app
/// comes back to the front (a window made meanwhile gets it too).
struct MobileAppearanceBridge: ViewModifier {
    @AppStorage(Setting.appearanceMode) private var appearance: String
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear(perform: apply)
            .onChange(of: appearance) { _, _ in apply() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { apply() } }
    }

    private func apply() {
        MobileAppearance.apply(
            MobileAppearance.interfaceStyle(appearance: appearance), to: UIApplication.shared.connectedScenes
        )
    }
}

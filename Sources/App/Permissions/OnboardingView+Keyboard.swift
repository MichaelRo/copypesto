// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

extension OnboardingView {
    /// The flow works from the keyboard alone: Left goes back a page, Right goes on where Continue is available, and
    /// Escape closes the window like its close button.
    var keyboardShortcuts: some View {
        Group {
            Button("Back") { stepBack() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!progress.canStepBack)
            Button("Next") { stepForward() }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!canStepForward)
            Button("Close") { dismissWindow() }
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    var canStepForward: Bool {
        switch progress.screen {
        case .shelf: !isSettingUpKeychain
        case .pasting: accessibilityGranted
        case .lock: false
        }
    }

    func stepBack() {
        var back = progress
        back.stepBack()
        withAnimation(Motion.animation(.pestoMove)) {
            shelfIntroduced = back.shelfIntroduced
            pastingConfirmed = back.pastingConfirmed
        }
    }

    func stepForward() {
        guard canStepForward else { return }
        switch progress.screen {
        case .shelf: setupKeychain()
        case .pasting: pastingConfirmed = true
        case .lock: break
        }
    }

    func dismissWindow() {
        NSApp.windows.first { $0.identifier?.rawValue == AccessibilityID.onboardingWindow }?.performClose(nil)
    }
}

// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

/// The welcome over the library: full screen on an iPhone, a centered form sheet on an iPad, where swiping it down is
/// Skip (ADR 0057).
struct WelcomePresentation: ViewModifier {
    @Environment(MobileAppState.self) private var appState
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.sheet(isPresented: isPresented, onDismiss: onDismiss) {
                WelcomeView().presentationSizing(.form)
            }
        } else {
            content.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) { WelcomeView() }
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { appState.showsWelcome }, set: { if !$0 { appState.showsWelcome = false } })
    }
}

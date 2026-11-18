// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The first-run welcome (ADR 0057): three steps moved by their buttons, with Skip on every step. It asks iOS for no
/// permission and fetches nothing while it is open.
struct WelcomeView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.pestoSurface) private var ground
    @Environment(\.pestoAccent) private var accent
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var model = WelcomeModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pages
                    .simultaneousGesture(swipeBack)
                footer
            }
            .background(ground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { appState.closeWelcome() }
                        .accessibilityIdentifier(MobileAccessibilityID.welcomeSkip)
                }
            }
        }
    }

    /// The three steps sit side by side and the row slides to the one in view; the others are hidden from VoiceOver
    /// and the screen, so a step that is not shown is not in the accessibility tree either.
    private var pages: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(WelcomeStep.allCases, id: \.self) { step in
                    page(step)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .accessibilityHidden(step != model.step)
                        .allowsHitTesting(step == model.step)
                }
            }
            .offset(x: -CGFloat(model.step.rawValue - 1) * proxy.size
                .width * (layoutDirection == .rightToLeft ? -1 : 1))
            .animation(Motion.animation(.pestoMove), value: model.step)
        }
        .clipped()
    }

    @ViewBuilder
    private func page(_ step: WelcomeStep) -> some View {
        switch step {
        case .keep: WelcomeKeepStep(isActive: model.step == .keep)
        case .choices: WelcomeChoicesStep()
        case .sync: WelcomeSyncStep(isActive: model.step == .sync)
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            dots
            VStack(spacing: 12) {
                if model.step == .sync {
                    Button { appState.closeWelcome(startingSync: true) } label: { buttonLabel("Turn On Sync") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(MobileAccessibilityID.welcomeTurnOnSync)
                    Button { appState.closeWelcome() } label: { buttonLabel("Not Now") }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(MobileAccessibilityID.welcomeNotNow)
                } else {
                    Button { advance() } label: { buttonLabel("Continue") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(MobileAccessibilityID.welcomeContinue)
                }
            }
            .controlSize(.large)
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    private func buttonLabel(_ title: LocalizedStringKey) -> some View {
        Text(title).frame(maxWidth: .infinity, minHeight: 28)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(WelcomeStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= model.step.rawValue ? accent : Color.primary.opacity(0.25))
                    .frame(width: 28, height: 4)
            }
        }
        .animation(Motion.animation(.pestoQuick), value: model.step)
        .accessibilityHidden(true)
    }

    private func advance() {
        model.goToNextStep()
    }

    private var swipeBack: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { drag in
            let toward = layoutDirection == .rightToLeft ? -drag.translation.width : drag.translation.width
            guard toward > 80, abs(drag.translation.height) < 60 else { return }
            model.goToPreviousStep()
        }
    }
}

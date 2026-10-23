// SPDX-License-Identifier: MIT
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import os
import PestoCore
import SwiftUI

/// Wraps any content with a biometric lock screen.
///
/// When `appState.isHistoryLocked` is `true`, the content is blurred and replaced by a lock prompt. Touch ID is asked
/// for inside that prompt as soon as the shelf is shown, so the shelf stays visible behind it; the system dialog is
/// used only for the password fallback, and where the embedded prompt is unavailable (no Touch ID, tests).
struct BiometricLockOverlay<Content: View>: View {
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.shelfActions) private var shelfActions: ShelfActionDispatcher
    @ViewBuilder let content: () -> Content
    @State private var lockMethod = LockMethod.current()
    @State private var biometricFailed = false
    @State private var shake: CGFloat = 0
    @State private var embeddedAttempt = 0
    @State private var shelfPromptAttempt = 0
    @State private var shelfPromptFailed = false
    /// Moves VoiceOver focus onto the lock screen as soon as it appears, instead of
    /// leaving focus on whatever was focused in the (now hidden) content behind it.
    @AccessibilityFocusState private var lockScreenFocused: Bool

    var body: some View {
        ZStack {
            content()
                .blur(radius: appState.isHistoryLocked ? ShelfLockCover.blurRadius : 0)
                .overlay {
                    // What the blur leaves of a picture's shape is flattened too (D-01).
                    if appState.isHistoryLocked { Color.opaqueSurface.opacity(ShelfLockCover.flatteningOpacity) }
                }
                .allowsHitTesting(!appState.isHistoryLocked)
                // Blurred is not hidden: the locked cards must not be readable by VoiceOver or automation.
                .accessibilityHidden(appState.isHistoryLocked)

            if appState.isHistoryLocked {
                lockScreen
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .accessibilityFocused($lockScreenFocused)
                    .onAppear { lockScreenFocused = true }
            } else if let request = appState.shelfAuthentication {
                shelfPrompt(request)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onChange(of: appState.isOverlayVisible) { _, visible in
            if !visible { shelfActions.finishShelfAuthentication(false) }
        }
        .animation(Motion.animation(.easeInOut(duration: 0.2)), value: appState.isHistoryLocked)
        .task(id: shouldPromptAutomatically) {
            biometricFailed = false
            embeddedAttempt = 0
            if shouldPromptAutomatically, !usesEmbeddedPrompt { await shelfActions.performBiometricUnlock() }
        }
    }

    private var shouldPromptAutomatically: Bool {
        HistoryLockPolicy.shouldPromptAutomatically(
            isLocked: appState.isHistoryLocked, isVisible: appState.isOverlayVisible
        )
    }

    private var usesEmbeddedPrompt: Bool {
        (LaunchMode.current.usesSystemIntegrations || RuntimeConfiguration.current.usesRealDevice)
            && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// The password or fallback unlock; a refusal shakes the glyph like a wrong password does.
    private func attemptUnlock() async {
        await shelfActions.performBiometricUnlock()
        if appState.isHistoryLocked { withAnimation(Motion.animation(.easeOut(duration: 0.4))) { shake += 1 } }
    }

    private var lockScreen: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .medium))
                .pestoQuiet()
                .modifier(ShakeEffect(progress: shake))

            Text("History locked")
                .scaledFont(size: 14, weight: .semibold)

            if usesEmbeddedPrompt {
                embeddedPrompt
            } else {
                unlockButton(title: lockMethod.unlockTitle) { await attemptUnlock() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History locked")
        .accessibilityIdentifier(AccessibilityID.lockOverlay)
        .padding(20)
        .glassPanelBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var embeddedPrompt: some View {
        if shouldPromptAutomatically, !biometricFailed {
            EmbeddedBiometricPrompt { errorCode in
                guard let errorCode else { return appState.completeUnlock() }
                if HistoryLockPolicy.shouldRetryBiometric(errorCode: errorCode, attempt: embeddedAttempt) {
                    embeddedAttempt += 1
                } else {
                    biometricFailed = true
                    withAnimation(Motion.animation(.easeOut(duration: 0.4))) { shake += 1 }
                }
            }
            .id(embeddedAttempt)
        } else {
            unlockButton(title: "Try Again") { biometricFailed = false }
        }
        Button("Use Password…") { Task { await attemptUnlock() } }
            .buttonStyle(.pestoLink)
            .controlSize(.small)
    }

    /// Touch ID for an action inside the shelf (showing a hidden clip), asked here so the shelf stays open.
    private func shelfPrompt(_ request: ShelfAuthenticationRequest) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "touchid")
                .font(.system(size: 26, weight: .medium))
                .pestoQuiet()
            Text(request.reason)
                .scaledFont(size: 13, weight: .semibold)
                .multilineTextAlignment(.center)
            if shelfPromptFailed {
                Button("Try Again") {
                    shelfPromptFailed = false
                    shelfPromptAttempt += 1
                }
                .buttonStyle(.pestoProminent)
                .controlSize(.small)
            } else {
                EmbeddedBiometricPrompt(reason: request.reason, label: "Confirm with Touch ID") { errorCode in
                    guard let errorCode else { return shelfActions.finishShelfAuthentication(true) }
                    if HistoryLockPolicy.shouldRetryBiometric(errorCode: errorCode, attempt: shelfPromptAttempt) {
                        shelfPromptAttempt += 1
                    } else {
                        shelfPromptFailed = true
                    }
                }
                .id(shelfPromptAttempt)
            }
            HStack(spacing: 14) {
                Button("Use Password\u{2026}") {
                    Task {
                        let ok = await appState.withSystemAuthenticationDialog {
                            await UserAuthenticator.current.authenticate(reason: request.reason)
                        }
                        shelfActions.finishShelfAuthentication(ok)
                    }
                }
                Button("Cancel") { shelfActions.finishShelfAuthentication(false) }
                    .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.pestoLink)
            .controlSize(.small)
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.reason)
        .accessibilityIdentifier(AccessibilityID.shelfAuthenticationPrompt)
        .glassPanelBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            shelfPromptAttempt = 0
            shelfPromptFailed = false
        }
    }

    private func unlockButton(title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: lockMethod.symbolName)
                .scaledFont(size: 12, weight: .semibold)
        }
        .buttonStyle(.pestoProminent)
        .controlSize(.small)
        .accessibilityIdentifier(AccessibilityID.unlockButton)
    }
}

/// Owns its own `LAContext`, so each appearance is a fresh attempt: it starts asking as soon as it is shown and reports
/// whether the fingerprint was accepted.
private struct EmbeddedBiometricPrompt: View {
    var reason = "Unlock your clipboard history"
    var label = "Unlock with Touch ID"
    /// `nil` means the fingerprint was accepted; otherwise the `LAError` code it ended with.
    let onResult: (Int?) -> Void
    @State private var context = LAContext()
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "BiometricLock")

    var body: some View {
        EmbeddedAuthenticationView(context: context)
            .frame(width: 130, height: 34)
            .accessibilityIdentifier(AccessibilityID.unlockButton)
            // The embedded LAAuthenticationView only exposed the identifier, not a spoken name.
            .accessibilityLabel(label)
            .task { await evaluate() }
            .onDisappear { context.invalidate() }
    }

    /// The shelf is a non-activating panel still fading in when this view appears, so the system can cancel the
    /// first attempt; waiting for the transition to finish keeps the prompt ready for the finger without a click.
    private func evaluate() async {
        try? await Task.sleep(for: HistoryLockPolicy.biometricStartDelay)
        guard !Task.isCancelled else { return }
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics, localizedReason: reason
            )
            onResult(nil)
        } catch {
            let code = (error as NSError).code
            Self.logger.info("Embedded Touch ID prompt ended with LAError code \(code, privacy: .public)")
            onResult(code)
        }
    }
}

private struct EmbeddedAuthenticationView: NSViewRepresentable {
    let context: LAContext

    func makeNSView(context _: Context) -> LAAuthenticationView {
        LAAuthenticationView(context: context, controlSize: .regular)
    }

    func updateNSView(_: LAAuthenticationView, context _: Context) {}
}

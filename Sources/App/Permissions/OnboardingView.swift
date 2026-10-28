// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

struct OnboardingView: View {
    var appState: AppState
    @Environment(\.pestoAccent) private var accent
    @State private var pollingTimer: Timer?
    @State var shelfIntroduced = false
    @State private var shelfTried = false
    @State var pastingConfirmed = false
    @State private var moreOptionsOpen = false
    @AppStorage(Setting.showMenuBarIcon) private var showsMenuBarIcon: Bool
    @AppStorage(Setting.keepsRemoteCopies) private var keepsRemoteCopies: Bool
    @AppStorage(Setting.biometricLockEnabled) private var biometricLockEnabled: Bool
    private let lockMethod = LockMethod.current()
    @State var accessibilityGranted = false
    @State private var accessibilitySkipped = false
    @State private var keychainGranted = false
    @State private var keychainError: String?
    @State var isSettingUpKeychain = false

    var progress: OnboardingProgress {
        OnboardingProgress(
            accessibilityGranted: accessibilityGranted,
            keyReady: keychainGranted,
            accessibilitySkipped: accessibilitySkipped,
            shelfIntroduced: shelfIntroduced,
            pastingConfirmed: pastingConfirmed
        )
    }

    private var shortcutLabel: String {
        HotkeyDescription.overlay(
            storedKeyCode: AppDefaults.store.value(for: Setting.overlayHotkeyKeyCode),
            storedModifiers: AppDefaults.store.value(for: Setting.overlayHotkeyModifiers)
        )
    }

    static let windowSize = CGSize(width: 480, height: 700)

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            // The window is fixed, but a long caption or a larger text size must not cut the last line off: the content
            // scrolls when it is taller than the window.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        progressDots
                            .padding(.top, 44)

                        Spacer(minLength: 20)

                        screenContent
                            .id(progress.screen)

                        Spacer(minLength: 20)

                        actionSection
                            .padding(.horizontal, 48)
                            .padding(.bottom, 28)
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        // The window's own title (set even though hidden, for VoiceOver) doesn't satisfy this
        // node's own description requirement — same two-level pattern as OverlayRootView (review
        // A-15). `.contain`, not `.ignore`, keeps every step and button individually reachable.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Pesto")
        .onChange(of: appState.isOverlayVisible) { _, visible in
            if visible { shelfTried = true }
        }
        .background { keyboardShortcuts }
        .onAppear { checkAndStartPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Screens

    private func stepLabel(_ title: String) -> String {
        "Step \(progress.screen.rawValue) of \(OnboardingProgress.stepCount). \(title)"
    }

    private var progressDots: some View {
        let current = progress.screen.rawValue
        return HStack(spacing: 8) {
            ForEach(OnboardingProgress.Screen.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= current ? accent : Color.primary.opacity(0.4))
                    .frame(width: 28, height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var screenContent: some View {
        switch progress.screen {
        case .shelf:
            shelfContent
        case .pasting:
            pastingContent
        case .lock:
            lastStepContent
        }
    }

    @ViewBuilder
    private func heroPicture(symbol: String, art: String?) -> some View {
        if let art {
            Image(art)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 120)
                .settleOnAppear(.hop)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                .background(BrandBackdropView().clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)))
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(accent)
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: 28).fill(Color.primary.opacity(0.07)))
                .accessibilityHidden(true)
        }
    }

    private func hero(symbol: String, art: String? = nil, title: String, text: String) -> some View {
        VStack(spacing: 14) {
            heroPicture(symbol: symbol, art: art)
            Text(LocalizedStringKey(title))
                .font(.title2.bold())
                .padding(.top, 6)
            Text(text)
                .font(.callout)
                .pestoQuiet()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
        }
        .padding(.horizontal, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stepLabel("\(title). \(text)"))
    }

    private var shelfContent: some View {
        VStack(spacing: 16) {
            heroPicture(symbol: "keyboard", art: "IllustrationWelcome")
            Text("Open the shelf from anywhere")
                .font(.title2.bold())
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(stepLabel("Open the shelf from anywhere, with \(shortcutLabel)"))
            ShortcutKeycaps(label: shortcutLabel)
                .scaleEffect(1.5)
                .padding(.vertical, 10)
                .accessibilityHidden(true)
            Text(shelfTried ? "That's your shelf. It starts empty. Esc closes it." :
                "Press it now. It starts empty. Esc closes it.")
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .accessibilityIdentifier(AccessibilityID.onboardingShelfTried)
            Button("Change the Shortcut") {
                appState.pendingSettingsSection = SettingsSection.shortcuts.rawValue
                appState.openSettingsFromOverlay?()
            }
            .buttonStyle(.pestoLink)
            .font(.callout)
            Label(
                keychainGranted
                    ? "Encryption key created in your Keychain"
                    : "Pesto creates its encryption key in your Keychain when you continue",
                systemImage: keychainGranted ? "checkmark.circle.fill" : "key.fill"
            )
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 48)
        }
        .padding(.horizontal, 24)
        .accessibilityIdentifier(AccessibilityID.onboardingShelfStep)
    }

    private var lastStepContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(accent))
                    .accessibilityHidden(true)
                Text("Pesto is ready.")
                    .font(.title2.bold())
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(stepLabel("Pesto is ready"))
                Text("Pesto lives in your menu bar. Press \(shortcutLabel) anywhere to open the shelf.")
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
                Text("Two choices, both optional. Settings has them later.")
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.75))
            }

            OnboardingCardStrip()

            choicesCard
        }
    }

    private var choicesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.authenticationAvailability != .unavailable {
                lockToggle
            }
            LoginItemToggle(title: "Launch Pesto at login")
            Button {
                withAnimation(Motion.animation(.pestoMove)) { moreOptionsOpen.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("More options")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(moreOptionsOpen ? 90 : 0))
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.pestoLink)
            .accessibilityIdentifier(AccessibilityID.onboardingMoreOptions)
            .accessibilityValue(moreOptionsOpen ? "Expanded" : "Collapsed")
            if moreOptionsOpen {
                Toggle(isOn: $showsMenuBarIcon) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show Pesto in the menu bar")
                        Text("You can always open the shelf with the shortcut.").pestoCaption()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier(AccessibilityID.onboardingMenuBarToggle)
                Toggle(isOn: $keepsRemoteCopies) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Keep copies from other devices")
                        Text("Clips you copy on an iPhone or iPad arrive through Universal Clipboard.")
                            .pestoCaption()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier(AccessibilityID.onboardingDevicesToggle)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
        .padding(.horizontal, 48)
    }

    private var accessibilityDescription: String {
        if accessibilityGranted {
            return "Accessibility Access is on, so Pesto can press ⌘V for you in the app you were using."
        }
        if accessibilitySkipped {
            return "Skipped. Pesto will copy the clip and you press ⌘V. You can turn this on later."
        }
        return "Accessibility Access lets Pesto press ⌘V for you in the app you were using. "
            + "Without it, Pesto copies the clip and you press ⌘V."
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 14) {
            switch progress.screen {
            case .shelf:
                VStack(spacing: 10) {
                    Button {
                        setupKeychain()
                    } label: {
                        if isSettingUpKeychain {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Creating encryption key…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(keychainError == nil ? "Continue" : "Try Again").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.pestoProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSettingUpKeychain)
                    .accessibilityIdentifier(AccessibilityID.onboardingContinueButton)

                    if let error = keychainError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.statusBad)
                            .multilineTextAlignment(.center)
                    }
                }
            case .pasting:
                VStack(spacing: 10) {
                    if accessibilityGranted {
                        Button {
                            pastingConfirmed = true
                        } label: {
                            Text("Continue").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pestoProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.onboardingContinueButton)
                    } else {
                        Button {
                            requestAccessibility()
                        } label: {
                            Label("Open Accessibility Settings", systemImage: "hand.raised.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pestoProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        Button("Continue Without Auto-Paste") {
                            accessibilitySkipped = true
                            pastingConfirmed = true
                            AppDefaults.store.set(true, for: Setting.declinedAutoPaste)
                        }
                        .buttonStyle(.pestoLink)
                        .accessibilityIdentifier(AccessibilityID.onboardingSkipAccessibilityButton)
                    }
                }
            case .lock:
                Button {
                    closeWindow()
                } label: {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pestoProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AccessibilityID.onboardingGetStartedButton)
            }

            if progress.canStepBack {
                Button("Back") { stepBack() }
                    .buttonStyle(.pestoLink)
                    .font(.callout)
                    .help("Go back a page (Left Arrow)")
                    .accessibilityIdentifier(AccessibilityID.onboardingBackButton)
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .pestoCaption()
                Text("What you copy is encrypted on this Mac.")
                    .pestoCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Polling

    private func checkAndStartPolling() {
        accessibilityGranted = AccessibilityAccess.isTrusted
        keychainGranted = BlobEncryption.isKeyAvailable

        guard !progress.isComplete else { return }

        // Poll only for Accessibility (the system dialog is out-of-process).
        // The key is created by the first step's Continue button, so the Keychain prompt follows a click.
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                let trusted = AccessibilityAccess.isTrusted
                if trusted != self.accessibilityGranted {
                    withAnimation(Motion.animation()) { self.accessibilityGranted = trusted }
                    if trusted { Announcer.announce(String(localized: "Accessibility is on. Auto-paste is ready.")) }
                }
                if self.accessibilityGranted { self.stopPolling() }
            }
        }
    }

    func setupKeychain() {
        isSettingUpKeychain = true
        keychainError = nil
        Task {
            do {
                // loadOrCreateKey() is silent on a fresh production install.
                // On dev builds with a changed signing identity, macOS may surface
                // an "Allow access?" system dialog inline — the UX the user requested.
                _ = try BlobEncryption().loadOrCreateKey()
                withAnimation(Motion.animation()) {
                    keychainGranted = true
                    isSettingUpKeychain = false
                    shelfIntroduced = true
                }
            } catch {
                isSettingUpKeychain = false
                keychainError = "Couldn\u{2019}t create the encryption key in your Keychain. "
                    + "Click Try Again."
                Announcer.announce(keychainError ?? "", priority: .high)
            }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func requestAccessibility() {
        // The prompt is what adds Pesto to the Accessibility list; the settings pane alone leaves it absent.
        AccessibilityPermission.requestWithPrompt()
        AccessibilityPermission.openSystemSettings()
    }

    private func closeWindow() {
        AppDefaults.store.set(true, for: Setting.hasOnboarded)
        appState.onboardingCompleted?()
        NSApp.windows.first { $0.identifier?.rawValue == AccessibilityID.onboardingWindow }?.close()
    }
}

private extension OnboardingView {
    var lockToggle: some View {
        Toggle(isOn: Binding(
            get: { biometricLockEnabled },
            set: { wantsOn in
                guard wantsOn else {
                    biometricLockEnabled = false
                    return
                }
                if HistoryLockPolicy.canSwitchOn(using: UserAuthenticator.current) {
                    biometricLockEnabled = true
                    HistoryLockPolicy.lockWasSwitchedOn()
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(lockMethod.settingsToggleTitle)
                Text("Require \(lockMethod.name) to view history.").pestoCaption()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(AccessibilityID.onboardingLockToggle)
    }

    /// The step that asks for Accessibility, with the note about macOS's own pasteboard alert where it can still
    /// appear.
    var pastingContent: some View {
        VStack(spacing: 12) {
            hero(
                symbol: "hand.point.up.left",
                title: "Let Pesto paste for you",
                text: accessibilityDescription
            )
            .accessibilityIdentifier(AccessibilityID.onboardingAccessibilityStep)
            if PasteboardCaptureAccess.current().asksOrWillAsk {
                Text(
                    "macOS will also ask whether Pesto may read what you copy. Choose Allow, or it cannot remember."
                )
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .accessibilityIdentifier(AccessibilityID.onboardingPasteboardNote)
            }
        }
    }
}

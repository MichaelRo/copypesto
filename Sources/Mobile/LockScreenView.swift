// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Drawn instead of the library while the history is locked (ADR 0054), so no card is ever drawn under it. It asks
/// once by itself each time Pesto comes to the front, as the Mac's lock asks when it is shown; a cancelled prompt
/// is not repeated, and the button stays.
struct LockScreenView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pestoSurface) private var ground
    @Environment(\.pestoAccent) private var accent
    @State private var askedThisVisit = false
    @State private var biometry = DeviceAuthenticationWords.biometry()

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: DeviceAuthenticationWords.symbol(for: biometry))
                .font(.system(.largeTitle))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("Your history is locked")
                .font(.title2.weight(.semibold))
            if appState.historyLock.canAuthenticate {
                Button(DeviceAuthenticationWords.unlockTitle(for: biometry)) { Task { await appState.unlockHistory() } }
                    .buttonStyle(.pestoProminent)
                    .accessibilityIdentifier(MobileAccessibilityID.unlockButton)
            } else {
                Text("This device has no passcode, so Pesto can\u{2019}t ask who you are.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Turn Off History Lock") { Task { await appState.turnOffHistoryLock() } }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(MobileAccessibilityID.lockScreen)
        .task(id: scenePhase) { await askIfShown() }
    }

    private func askIfShown() async {
        if scenePhase == .background { askedThisVisit = false }
        guard !askedThisVisit, HistoryLockPolicy.shouldPromptAutomatically(
            isLocked: appState.isHistoryLocked, isVisible: scenePhase == .active
        ), appState.historyLock.canAuthenticate else { return }
        askedThisVisit = true
        try? await Task.sleep(for: HistoryLockPolicy.biometricStartDelay)
        guard !Task.isCancelled else { return }
        await appState.unlockHistory()
    }
}

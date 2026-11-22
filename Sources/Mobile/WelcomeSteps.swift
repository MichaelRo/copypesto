// SPDX-License-Identifier: MIT
import LocalAuthentication
import PestoCore
import SwiftUI

struct WelcomeKeepStep: View {
    let isActive: Bool

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var actionRow: LocalizedStringResource {
        isPad ? "Run it from Siri or Shortcuts." : "Run it from Siri, Shortcuts or the Action Button."
    }

    private var privacyLine: String {
        isPad
            ? String(localized: "iPad keeps your clipboard private, so Pesto adds a copy only when you ask.")
            : String(localized: "iPhone keeps your clipboard private, so Pesto adds a copy only when you ask.")
    }

    var body: some View {
        WelcomePage(
            stepNumber: WelcomeStep.keep.rawValue, isActive: isActive, title: String(localized: "Keep what you copy"),
            line: privacyLine
        ) {
            WelcomeKeepArt(isActive: isActive)
        } content: {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeRow(
                    symbol: "doc.on.clipboard", title: "Paste",
                    text: "Press Paste in Pesto to add what you just copied."
                )
                WelcomeRow(
                    symbol: "square.and.arrow.up", title: "Share",
                    text: "Share text, links and pictures to Pesto from any app."
                )
                WelcomeRow(symbol: "plus.square.on.square", title: "Add Clipboard to Pesto", text: actionRow)
            }
            .padding(.top, 4)
            Text("Copies an app marks as private are never kept.")
                .font(.footnote)
                .pestoQuiet()
                .multilineTextAlignment(.center)
        }
        .accessibilityIdentifier(MobileAccessibilityID.welcomeKeepStep)
    }
}

struct WelcomeChoicesStep: View {
    let isActive: Bool
    @Environment(MobileAppState.self) private var appState
    @AppStorage(Setting.linkPreviews) private var linkPreviews: Bool
    @AppStorage(Setting.biometricLockEnabled) private var lockEnabled: Bool
    @AppStorage(Setting.showsClipsOutsideWhileLocked) private var showsClipsOutside: Bool
    @State private var biometry = DeviceAuthenticationWords.biometry()
    @State private var showsQuickInsertSetup = false

    var body: some View {
        WelcomePage(
            stepNumber: WelcomeStep.choices.rawValue, isActive: isActive, title: String(localized: "Two choices"),
            line: String(localized: "You can change both in Settings.")
        ) {
            EmptyView()
        } content: {
            VStack(spacing: 0) {
                Toggle(isOn: $linkPreviews) {
                    WelcomeChoiceText(
                        title: String(localized: "Load link previews"),
                        caption: String(localized: """
                        Pesto asks a link\u{2019}s site for its title and picture. \
                        The site sees your IP address.
                        """)
                    )
                }
                .accessibilityIdentifier(MobileAccessibilityID.welcomeLinkPreviews)
                Divider().padding(.vertical, 14)
                Toggle(isOn: lockBinding) {
                    WelcomeChoiceText(
                        title: DeviceAuthenticationWords.lockToggleTitle(for: biometry),
                        caption: DeviceAuthenticationWords.lockCaption(
                            for: biometry, canAuthenticate: lockEnabled || appState.historyLock.canAuthenticate,
                            showsClipsOutside: showsClipsOutside
                        )
                    )
                }
                .disabled(!lockEnabled && !appState.historyLock.canAuthenticate)
                .accessibilityIdentifier(MobileAccessibilityID.welcomeLock)
            }
            .padding(16)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 20))
            .padding(.top, 8)
            Button("Set up Keyboard & AutoFill\u{2026}") {
                showsQuickInsertSetup = true
            }
            .font(.subheadline.weight(.medium))
            .padding(.top, 12)
        }
        .sheet(isPresented: $showsQuickInsertSetup) {
            QuickInsertSetupSheet()
        }
        .accessibilityIdentifier(MobileAccessibilityID.welcomeChoicesStep)
    }

    private var lockBinding: Binding<Bool> {
        Binding(get: { lockEnabled }, set: { wantsOn in
            Task {
                if wantsOn { _ = await appState.turnOnHistoryLock() } else { _ = await appState.turnOffHistoryLock() }
            }
        })
    }
}

private struct WelcomeChoiceText: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body)
            Text(caption).font(.footnote).pestoQuiet()
        }
    }
}

struct WelcomeSyncStep: View {
    let isActive: Bool
    @Environment(MobileAppState.self) private var appState

    private var isSyncOn: Bool {
        appState.sync?.isEnabled == true
    }

    var body: some View {
        WelcomePage(
            stepNumber: WelcomeStep.sync.rawValue, isActive: isActive,
            title: isSyncOn
                ? String(localized: "Sync is on")
                : String(localized: "Your clips on every device"),
            line: isSyncOn
                ? String(localized: """
                Your clips stay in step through your chosen sync folder. \
                No server: clips are sealed so only your devices can open them.
                """)
                : String(localized: """
                Sync your iPhone, iPad and Mac through a folder you choose, such as iCloud Drive. \
                No server: clips are sealed so only your devices can open them.
                """)
        ) {
            WelcomeSyncArt(isActive: isActive)
        } content: {
            EmptyView()
        }
        .accessibilityIdentifier(MobileAccessibilityID.welcomeSyncStep)
    }
}

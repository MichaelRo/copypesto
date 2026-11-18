// SPDX-License-Identifier: MIT
import LocalAuthentication
import PestoCore
import SwiftUI

/// What every step has in common: the art (hidden at accessibility sizes), the title that says which step this is to
/// VoiceOver, the line under it, then the step's own content, all in a scroll view above the pinned buttons.
struct WelcomePage<Art: View, Content: View>: View {
    let stepNumber: Int
    let title: String
    let line: String
    @ViewBuilder var art: Art
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    if !typeSize.isAccessibilitySize {
                        art.frame(maxWidth: 340).padding(.bottom, 4)
                    }
                    VStack(spacing: 10) {
                        Text(title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .accessibilityLabel(Text("Step \(stepNumber) of \(WelcomeModel.stepCount). \(title)"))
                            .accessibilityAddTraits(.isHeader)
                        Text(line)
                            .font(.body)
                            .pestoQuiet()
                            .multilineTextAlignment(.center)
                    }
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct WelcomeKeepStep: View {
    let isActive: Bool

    private var actionRow: LocalizedStringResource {
        UIDevice.current.userInterfaceIdiom == .pad
            ? "Run it from Siri or Shortcuts." : "Run it from Siri, Shortcuts or the Action Button."
    }

    var body: some View {
        WelcomePage(
            stepNumber: WelcomeStep.keep.rawValue, title: String(localized: "Keep what you copy"),
            line: String(localized: "iPhone keeps your clipboard private, so Pesto adds a copy only when you ask.")
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

private struct WelcomeRow: View {
    let symbol: String
    let title: LocalizedStringResource
    let text: LocalizedStringResource
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 32, alignment: typeSize.isAccessibilitySize ? .leading : .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).pestoQuiet()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct WelcomeChoicesStep: View {
    @Environment(MobileAppState.self) private var appState
    @AppStorage(Setting.linkPreviews) private var linkPreviews: Bool
    @AppStorage(Setting.biometricLockEnabled) private var lockEnabled: Bool
    @State private var biometry = DeviceAuthenticationWords.biometry()

    var body: some View {
        WelcomePage(
            stepNumber: WelcomeStep.choices.rawValue, title: String(localized: "Two choices"),
            line: String(localized: "You can change both in Settings.")
        ) {
            EmptyView()
        } content: {
            VStack(spacing: 0) {
                Toggle(isOn: $linkPreviews) {
                    WelcomeChoiceText(
                        title: String(localized: "Load link previews"),
                        caption: String(
                            localized: "Pesto asks a link\u{2019}s site for its title and picture. The site sees your address."
                        )
                    )
                }
                .accessibilityIdentifier(MobileAccessibilityID.welcomeLinkPreviews)
                Divider().padding(.vertical, 14)
                Toggle(isOn: lockBinding) {
                    WelcomeChoiceText(
                        title: DeviceAuthenticationWords.lockToggleTitle(for: biometry),
                        caption: DeviceAuthenticationWords.lockCaption(for: biometry)
                    )
                }
                .disabled(!lockEnabled && !appState.historyLock.canAuthenticate)
                .accessibilityIdentifier(MobileAccessibilityID.welcomeLock)
            }
            .padding(16)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 20))
            .padding(.top, 8)
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

    var body: some View {
        WelcomePage(
            stepNumber: WelcomeStep.sync.rawValue, title: String(localized: "Your Mac\u{2019}s clips, here too"),
            line: String(
                localized: "Sync goes through a folder you choose, such as iCloud Drive. No server: clips are sealed so only your devices can open them."
            )
        ) {
            WelcomeSyncArt(isActive: isActive)
        } content: {
            EmptyView()
        }
        .accessibilityIdentifier(MobileAccessibilityID.welcomeSyncStep)
    }
}

// SPDX-License-Identifier: MIT
import SwiftUI

/// The one-time tip after the first pin or snippet (ADR 0057): a card in the library, not a modal. Turn On switches
/// Pesto's AutoFill setting on and opens iOS's AutoFill settings, while Set Up opens the guided checklist for both
/// AutoFill and Pesto Keyboard.
struct AutoFillTipBanner: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("Insert your clips in any app. Clips only, never passwords.")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilitySortPriority(4)
                Button("Not Now", systemImage: "xmark") { appState.dismissAutoFillTip() }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                    .contentShape(.rect)
                    .padding(.top, -10)
                    .padding(.trailing, -10)
                    .accessibilitySortPriority(1)
                    .accessibilityIdentifier(MobileAccessibilityID.autoFillTipDismiss)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actionButtons }
                VStack(alignment: .leading, spacing: 8) { actionButtons }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .mobileGlassChrome(in: .rect(cornerRadius: 22), interactive: true)
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(MobileAccessibilityID.autoFillTip)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            Task { await appState.turnOnAutoFillFromTip() }
        } label: {
            Text("Turn On")
                .frame(minHeight: TouchTarget.minimum - 10)
        }
        .buttonStyle(.pestoProminent)
        .frame(minHeight: TouchTarget.minimum)
        .contentShape(.rect)
        .accessibilitySortPriority(3)
        .accessibilityHint("Opens AutoFill settings")
        .accessibilityIdentifier(MobileAccessibilityID.autoFillTipTurnOn)

        Button {
            appState.dismissAutoFillTip()
            library.showsQuickInsertSetup = true
        } label: {
            Text("Set Up\u{2026}")
                .frame(minHeight: TouchTarget.minimum - 10)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 7))
        .frame(minHeight: TouchTarget.minimum)
        .contentShape(.rect)
        .accessibilitySortPriority(2)
        .accessibilityHint("Opens Keyboard and AutoFill setup")
        .accessibilityIdentifier(MobileAccessibilityID.autoFillTipSetUp)
    }
}

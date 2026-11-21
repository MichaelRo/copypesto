// SPDX-License-Identifier: MIT
import SwiftUI

/// The one-time tip after the first pin or snippet (ADR 0057): a card in the library, not a modal. Turn On switches
/// Pesto's AutoFill setting on and opens iOS's AutoFill settings, where Pesto is switched on.
struct AutoFillTipBanner: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text("Insert your clips in any app. Clips only, never passwords. You switch Pesto on in Settings.")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("Turn On") { Task { await appState.turnOnAutoFillFromTip() } }
                    .buttonStyle(.pestoProminent)
                    .accessibilityHint("Opens AutoFill settings")
                    .accessibilityIdentifier(MobileAccessibilityID.autoFillTipTurnOn)
                Button("Not Now", systemImage: "xmark") { appState.dismissAutoFillTip() }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                    .accessibilityIdentifier(MobileAccessibilityID.autoFillTipDismiss)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .mobileGlassChrome(in: .rect(cornerRadius: 22), interactive: true)
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(MobileAccessibilityID.autoFillTip)
    }
}

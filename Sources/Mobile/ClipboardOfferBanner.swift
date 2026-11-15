// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// "Add what you copied", offered when the clipboard changed while Pesto was away. Its action is the system Paste
/// button, so adding it never asks for permission; the clipboard is not read to show it.
struct ClipboardOfferBanner: View {
    @Environment(MobileAppState.self) private var appState

    var body: some View {
        HStack(spacing: 10) {
            Text("Add what you copied")
            Spacer(minLength: 8)
            PasteButton(supportedContentTypes: ItemProviderCapture.acceptedTypes) { providers in
                Task { await appState.takeClipboardOffer(providers) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            Button("Not Now", systemImage: "xmark") { appState.dismissClipboardOffer() }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(MobileAccessibilityID.clipboardOffer)
    }
}

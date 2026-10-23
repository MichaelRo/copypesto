// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Settings → Privacy → Other devices: whether a copy from your iPhone or another Mac (Universal Clipboard) is kept.
struct OtherDevicesSettings: View {
    @AppStorage(Setting.keepsRemoteCopies) private var keepsRemoteCopies: Bool

    var body: some View {
        Section {
            Toggle("Keep copies from other devices", isOn: $keepsRemoteCopies)
                .accessibilityIdentifier(AccessibilityID.settingsChoice("keepsRemoteCopies", "toggle"))
                .settingsRow("Keep copies from other devices")
            Text(
                "Copies from your iPhone, iPad or another Mac signed in to your Apple Account reach this Mac " +
                    "through Universal Clipboard. Off, Pesto keeps only what you copy on this Mac; pasting with " +
                    "\u{2318}V still works. On, they join your history and can be found with the Other Devices " +
                    "filter, which stays in search while any of them is in your history. Photos and files copied on " +
                    "another device are not kept: macOS keeps them where Pesto may not read them and deletes them " +
                    "as soon as you copy something else. \u{2318}V still pastes them, and they count under " +
                    "Left out of your history."
            )
            .pestoCaption()
        } header: {
            Text("Other devices")
        }
    }
}

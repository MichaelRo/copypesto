// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Settings → Privacy → Other devices & Network: Universal Clipboard, screen sharing protection, and link previews.
struct OtherDevicesSettings: View {
    @AppStorage(Setting.keepsRemoteCopies) private var keepsRemoteCopies: Bool
    @AppStorage(Setting.screenSharingPrivacy) private var screenSharingPrivacy: Bool
    @AppStorage(Setting.linkPreviews) private var linkPreviews: Bool

    var body: some View {
        Section {
            HStack(spacing: 6) {
                Toggle("Keep copies from other devices", isOn: $keepsRemoteCopies)
                    .accessibilityIdentifier(AccessibilityID.settingsChoice("keepsRemoteCopies", "toggle"))
                Spacer()
                InfoPopoverButton(
                    "Other devices",
                    message: "Copies from your iPhone, iPad or another Mac signed in to your Apple Account reach " +
                        "this Mac through Universal Clipboard. Off, Pesto keeps only what you copy on this Mac; " +
                        "pasting with \u{2318}V still works. On, they join your history and can be found with " +
                        "the Other Devices filter. Photos and files copied on another device are not kept."
                )
            }
            .settingsRow("Keep copies from other devices")

            HStack(spacing: 6) {
                Toggle("Hide contents during screen sharing", isOn: $screenSharingPrivacy)
                Spacer()
                InfoPopoverButton(
                    "Screen sharing",
                    message: "Clip contents are covered while a display is mirrored, a known sharing or recording " +
                        "app is open (Zoom, Teams, FaceTime, Discord, OBS), or a browser shows its " +
                        "\u{201C}sharing your screen\u{201D} bar. Safari and single-tab shares are not seen: " +
                        "choose Hide Clip Contents in the menu bar for those."
                )
            }
            .settingsRow("Hide contents during screen sharing")

            HStack(spacing: 6) {
                Toggle("Load link previews", isOn: $linkPreviews)
                    .accessibilityIdentifier(AccessibilityID.settingsChoice("linkPreviews", "toggle"))
                Spacer()
                InfoPopoverButton(
                    "Link previews",
                    message: "Link previews show a link\u{2019}s title and picture on its card. Pesto has to ask " +
                        "the website, so the site can see a request from your Mac."
                )
            }
            .settingsRow("Load link previews")
        } header: {
            Text("Other devices & Network")
        } footer: {
            Text("Everything here is optional. Only link previews ever contact another server.")
                .pestoCaption()
        }
    }
}

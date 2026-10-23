// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// General → Apple Intelligence: the one switch over every on-device AI feature, and whether this Mac can run them.
struct AppleIntelligenceSettings: View {
    @AppStorage(Setting.appleIntelligenceEnabled) private var enabled: Bool
    @Environment(\.pestoAccent) private var accent

    private var system: AIAvailability {
        AIAvailability.system
    }

    var body: some View {
        Section {
            if system.presentation == .hidden {
                Label(system.message, systemImage: "minus.circle")
                    .pestoQuiet()
                    .accessibilityIdentifier(AccessibilityID.aiUnavailableNotice)
            } else {
                Toggle("Use Apple Intelligence", isOn: $enabled)
                    .accessibilityIdentifier(AccessibilityID.settingsChoice("appleIntelligence", "toggle"))
                status
            }
        } header: {
            Text("Apple Intelligence").settingsRow("Apple Intelligence")
        } footer: {
            Text(
                "Powers Summarize, Translate and Extract, Describe Image, picture screening for the content filter " +
                    "and sentence understanding in Ask. It runs on this Mac with Apple\u{2019}s on-device model: no " +
                    "account, no key, and nothing you copy is sent anywhere."
            )
            .pestoCaption()
        }
    }

    @ViewBuilder
    private var status: some View {
        if !enabled {
            Label("Turned off. The AI actions are grayed out.", systemImage: "minus.circle")
                .pestoQuiet()
        } else if system.isAvailable {
            Label {
                Text("Ready on this Mac")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
            }
            if !AppleIntelligenceClient.supportsVision {
                Text("Describe Image needs a model that can read pictures, which this Mac\u{2019}s does not have yet.")
                    .pestoCaption()
            }
        } else {
            Label(system.message, systemImage: "exclamationmark.circle")
                .pestoQuiet()
                .accessibilityIdentifier(AccessibilityID.aiUnavailableNotice)
            if system.canBeFixedInSystemSettings {
                Button("Open Apple Intelligence Settings\u{2026}") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

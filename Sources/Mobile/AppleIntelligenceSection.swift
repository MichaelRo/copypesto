// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// Settings → Apple Intelligence: the one switch over every on-device AI feature (AI Actions, Describe Image and the
/// sentence understanding in Ask), and whether this device can run them (ADR 0005).
struct AppleIntelligenceSection: View {
    @AppStorage(Setting.appleIntelligenceEnabled) private var enabled: Bool
    @Environment(\.pestoAccent) private var accent

    private var system: AIAvailability {
        AIAvailability.system
    }

    var body: some View {
        Section {
            if system.presentation == .hidden {
                Label(system.message, systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MobileAccessibilityID.aiUnavailableNotice)
            } else {
                Toggle("Use Apple Intelligence", isOn: $enabled)
                    .accessibilityIdentifier(MobileAccessibilityID.appleIntelligenceToggle)
                status
            }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text(
                """
                Powers AI Actions, Describe Image and sentence understanding in Ask. It runs on this device with \
                Apple\u{2019}s on-device model: no account, no key, and nothing you copy is sent anywhere.
                """
            )
        }
    }

    @ViewBuilder
    private var status: some View {
        if !enabled {
            Label("Turned off. AI Actions are grayed out.", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        } else if system.isAvailable {
            Label {
                Text("Ready on this device")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
            }
            if !AppleIntelligenceClient.supportsVision {
                Text(
                    "Describe Image needs a model that can read pictures, which this device\u{2019}s does not have yet."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } else {
            Label(system.message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(MobileAccessibilityID.aiUnavailableNotice)
            if system.canBeFixedInSystemSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
    }
}

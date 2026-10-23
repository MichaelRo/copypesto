// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import ServiceManagement
import SwiftUI

struct LoginItemToggle: View {
    let title: String
    private let service = LoginItemService()
    @State private var status = LoginItemService().status
    @State private var failure: String?

    var body: some View {
        Toggle(isOn: Binding(
            get: { status.isOn },
            set: { apply(service.setEnabled($0)) }
        )) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(AccessibilityID.launchAtLoginToggle)
        .settingsRow("Launch Pesto at login")
        .onAppear {
            status = service.status
            service.logStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            status = service.status
        }

        if failure == nil, status != .requiresApproval {
            Text("Pesto opens quietly in the menu bar each time you log in.").pestoCaption()
        }

        if let failure {
            Text(Self.explanation(for: failure))
                .pestoCaption()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.launchAtLoginUnavailable)
        }

        if status == .requiresApproval {
            HStack {
                Text("Allow Pesto in System Settings → Login Items to finish enabling this.")
                    .pestoCaption()
                Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    .controlSize(.small)
            }
        }
    }

    private func apply(_ change: LoginItemChange) {
        status = change.status
        failure = change.failure
    }

    private static func explanation(for failure: String) -> String {
        let location = InstallLocation.evaluate(bundlePath: Bundle.main.bundlePath).launchAtLoginUnavailableExplanation
        return "\(location) macOS said: \(failure)"
    }
}

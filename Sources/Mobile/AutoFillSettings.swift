// SPDX-License-Identifier: MIT
import AuthenticationServices
import UIKit

/// Opens iOS's AutoFill provider settings, where Pesto is switched on; where that fails, the app's own settings page.
enum AutoFillSettings {
    @MainActor
    static func open() async {
        if await ASSettingsHelper.requestToTurnOnCredentialProviderExtension() {
            return
        }
        await openSettings()
    }

    @MainActor
    static func openSettings() async {
        do {
            try await ASSettingsHelper.openCredentialProviderAppSettings()
        } catch {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            await UIApplication.shared.open(url)
        }
    }
}

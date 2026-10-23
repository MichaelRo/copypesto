// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// Reads the facts About copies for a bug report. Counts and switches only: nothing from the history.
enum DiagnosticsFacts {
    static func current(store: UserDefaults = AppDefaults.store) -> DiagnosticsReport.Facts {
        let info = Bundle.main.infoDictionary
        return DiagnosticsReport.Facts(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            hardware: hardwareModel(),
            architecture: architecture,
            isDevelopmentBuild: BuildKind.isDevelopment,
            switches: [
                ("Accessibility", AccessibilityAccess.isTrusted),
                ("History lock", store.value(for: Setting.biometricLockEnabled)),
                ("Link previews", store.value(for: Setting.linkPreviews)),
                ("Apple Intelligence", store.value(for: Setting.appleIntelligenceEnabled)),
                ("Cursor menu", store.value(for: Setting.opensQuickMenuAtCursor))
            ],
            keepsClipsForDays: keepsClipsForDays(RetentionPolicy.fromDefaults(store))
        )
    }

    private static func keepsClipsForDays(_ policy: RetentionPolicy) -> Int {
        policy.maxAge.isFinite ? Int(policy.maxAge / 86_400) : 0
    }

    private static var architecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [UInt8](repeating: 0, count: size)
        guard size > 0, sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
    }
}

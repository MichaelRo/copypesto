// SPDX-License-Identifier: MIT
import Foundation

/// The version as every surface prints it, so About and Settings never disagree.
public enum AppVersion {
    public static func displayString(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "\u{2013}"
        let build = info?["CFBundleVersion"] as? String ?? "\u{2013}"
        return String(localized: "Version \(version) (\(build))")
    }
}

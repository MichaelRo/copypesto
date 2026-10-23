// SPDX-License-Identifier: MIT
import Foundation

/// Whether this copy of Pesto was built on a developer's Mac by `make run` or `make install`. Such a build is the
/// same app as the shipped one (same bundle identifier, store and Keychain key), so it must not take the official
/// updates and replace what the developer is working on.
public enum BuildKind {
    public static func isDevelopment(infoValue: Any?) -> Bool {
        (infoValue as? String) == "YES"
    }

    public static var isDevelopment: Bool {
        isDevelopment(infoValue: Bundle.main.object(forInfoDictionaryKey: "PestoDevelopmentBuild"))
    }
}

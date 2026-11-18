// SPDX-License-Identifier: MIT
import Foundation
import Security

/// The iOS app holds three Keychain groups (its own, AutoFill's and the widget's, ADR 0051 and 0052), and a query that
/// names none searches all of them. Every query for the app's own items (the history, inbox, device and sync keys) is
/// pinned to the app's own group on iOS. A Mac query is left exactly as it was, so no Mac item is looked up anew.
public enum AppKeychainGroup {
    /// The app's own group on iOS (`$(AppIdentifierPrefix)` and the bundle ID); nil on the Mac, and nil when the bundle
    /// does not carry the prefix (a bundle that is not the app).
    public static let own: String? = {
        #if os(iOS)
        ownGroup(prefix: Bundle.main.object(forInfoDictionaryKey: AppIdentity.appIdentifierPrefixInfoKey) as? String)
        #else
        nil
        #endif
    }()

    static func ownGroup(prefix: String?) -> String? {
        guard let prefix, !prefix.isEmpty else { return nil }
        return prefix + AppIdentity.bundleID
    }

    public static func pinned(_ query: [String: Any], to group: String? = own) -> [String: Any] {
        guard let group else { return query }
        var pinned = query
        pinned[kSecAttrAccessGroup as String] = group
        return pinned
    }
}

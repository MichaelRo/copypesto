// SPDX-License-Identifier: MIT
import Foundation
import Security

/// Whether this process may share the widget's snapshot and key (ADR 0052, ADR 0059): its signed entitlements claim the
/// app group and the widget's Keychain group. On the Mac only a release signed with both provisioning profiles does,
/// and without both nothing opens the group container (macOS 15 would ask the person) or touches that Keychain group.
public struct WidgetSharing: Equatable, Sendable {
    /// The widget's full Keychain group, team prefix included.
    public let keychainGroup: String

    public init(keychainGroup: String) {
        self.keychainGroup = keychainGroup
    }

    public static let appGroupsEntitlement = "com.apple.security.application-groups"
    public static let keychainGroupsEntitlement = "keychain-access-groups"

    /// The grant the two entitlement values make: the app group, and one Keychain group that is a team prefix followed
    /// by the widget's group name. Anything else (one of them missing, an unexpanded `$(…)`, no prefix) is no grant.
    public static func grant(appGroups: [String]?, keychainGroups: [String]?) -> WidgetSharing? {
        guard appGroups?.contains(AppIdentity.appGroupID) == true else { return nil }
        let suffix = "." + AppIdentity.widgetKeychainGroupName
        let group = keychainGroups?.first { group in
            guard group.hasSuffix(suffix), !group.contains("$(") else { return false }
            let prefix = group.dropLast(suffix.count)
            return !prefix.isEmpty && prefix.allSatisfy { $0.isLetter || $0.isNumber }
        }
        return group.map(WidgetSharing.init(keychainGroup:))
    }

    /// The running process's grant. Entitlements cannot change while it runs, so it is read once.
    public static let current: WidgetSharing? = {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        func strings(_ name: String) -> [String]? {
            SecTaskCopyValueForEntitlement(task, name as CFString, nil) as? [String]
        }
        return grant(appGroups: strings(appGroupsEntitlement), keychainGroups: strings(keychainGroupsEntitlement))
        #else
        return nil
        #endif
    }()

    /// The widget's Keychain group for this process: on the Mac from its entitlements, on iOS from the team prefix the
    /// bundle carries (`PestoAppIdentifierPrefix`), as before.
    public static func keychainGroup(in bundle: Bundle = .main) -> String? {
        #if os(macOS)
        current?.keychainGroup
        #else
        AppIdentity.widgetKeychainGroup(in: bundle)
        #endif
    }
}

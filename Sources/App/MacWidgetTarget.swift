// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import WidgetKit

/// Where the Mac keeps the Recent Clips snapshot and its key, and what WidgetKit says (ADR 0059). Only a normal launch
/// of a build signed with both provisioning profiles has one; every other build, a hosted test and a UI-test launch get
/// nil, so they never open the group container, ask WidgetKit or touch the widget's Keychain group.
@MainActor
enum MacWidgetTarget {
    static var current: WidgetSnapshotKeeper.Target? {
        guard LaunchMode.current == .normal, let group = WidgetSharing.keychainGroup(),
              let file = SealedGroupFile.current(.widgetSnapshot) else { return nil }
        return WidgetSnapshotKeeper.Target(
            file: file,
            keys: SharedFileKeyStore(
                secrets: SharedKeychainSecretStore(accessGroup: group), account: AppIdentity.widgetKeyAccount
            ),
            isInstalled: {
                let widgets = try? await WidgetCenter.shared.currentConfigurations()
                return widgets?.contains { $0.kind == AppIdentity.widgetKind } ?? false
            },
            reload: { WidgetCenter.shared.reloadTimelines(ofKind: AppIdentity.widgetKind) }
        )
    }
}

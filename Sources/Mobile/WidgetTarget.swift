// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import WidgetKit

/// Where the app keeps the widget's snapshot and its key, and whether a Pesto widget is installed (ADR 0052). Only a
/// normal launch has one: a hosted test names its own folder, key storage and answer; a UI-test launch has none, so it
/// never touches the real app group, Keychain group or widgets.
@MainActor
struct WidgetTarget {
    let file: SealedGroupFile
    let keys: SharedFileKeyStore
    let isInstalled: @MainActor () async -> Bool
    let reload: @MainActor () -> Void
    var isEnabled: @MainActor () -> Bool = { AppDefaults.store.value(for: Setting.widgetsEnabled) }

    static func matchesInstalledKind(_ kind: String) -> Bool {
        AppIdentity.widgetKinds.contains(kind)
    }

    static var current: WidgetTarget? {
        guard LaunchMode.current == .normal, let file = SealedGroupFile.current(.widgetSnapshot) else { return nil }
        let secrets = SharedKeychainSecretStore(accessGroup: AppIdentity.widgetKeychainGroup(in: .main))
        return WidgetTarget(
            file: file, keys: SharedFileKeyStore(secrets: secrets, account: AppIdentity.widgetKeyAccount),
            isInstalled: {
                let widgets = try? await WidgetCenter.shared.currentConfigurations()
                return widgets?.contains { matchesInstalledKind($0.kind) } ?? false
            },
            reload: {
                for kind in AppIdentity.widgetKinds {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind)
                }
            }
        )
    }
}

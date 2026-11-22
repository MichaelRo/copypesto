// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// Where the app keeps the AutoFill set and its key, and whether the person wants one (ADR 0051). A hosted test names
/// its own folder and key storage; a UI-test launch keeps the key in memory and the file in its own folder.
@MainActor
struct QuickInsertTarget {
    let file: QuickInsertFile
    let keys: QuickInsertKeyStore
    let isEnabled: @MainActor () -> Bool
    /// The collections and the after-insert choice the person made for the keyboard (ADR 0062).
    var options: @MainActor () -> QuickInsertSelection.Options = {
        QuickInsertSelection.Options(
            storedCollections: AppDefaults.store.value(for: Setting.keyboardCollections),
            returnsAfterInsert: AppDefaults.store.value(for: Setting.keyboardReturnsAfterInsert),
            keyboardSize: KeyboardSize(rawValue: AppDefaults.store.value(for: Setting.keyboardSize)) ?? .medium,
            accent: MobileAppState.widgetTheme(),
            keyboardEnabled: AppDefaults.store.value(for: Setting.keyboardEnabled),
            autoFillEnabled: AppDefaults.store.value(for: Setting.autoFillEnabled)
        )
    }

    private static let uiTestSecrets = InMemorySecretStore()

    static var current: QuickInsertTarget? {
        let mode = LaunchMode.current
        guard mode != .hostedTests, let file = QuickInsertFile.current else { return nil }
        let secrets: any SecretStoring = mode == .uiTest
            ? uiTestSecrets
            : SharedKeychainSecretStore(accessGroup: AppIdentity.quickInsertKeychainGroup(in: .main))
        return QuickInsertTarget(
            file: file, keys: QuickInsertKeyStore(secrets: secrets),
            isEnabled: {
                let store = AppDefaults.store
                return store.value(for: Setting.keyboardEnabled)
                    || store.value(for: Setting.autoFillEnabled)
                    || (store.object(forKey: Setting.keyboardEnabled.name) == nil
                        && store.object(forKey: Setting.autoFillEnabled.name) == nil
                        && store.value(for: Setting.quickInsertEnabled))
            }
        )
    }
}

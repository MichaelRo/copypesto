// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// `@AppStorage(Setting.appTheme)`: the key and its default come from the registry. The root view points
/// `defaultAppStorage` at `AppDefaults.store`, so a test launch never reads the person's own preferences.
extension AppStorage {
    init(_ key: SettingKey<Int>) where Value == Int {
        self.init(wrappedValue: key.defaultValue, key.name)
    }

    init(_ key: SettingKey<String>) where Value == String {
        self.init(wrappedValue: key.defaultValue, key.name)
    }
}

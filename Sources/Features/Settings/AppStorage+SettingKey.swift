// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// `@AppStorage(Setting.cardSize)`: the key and its default come from the registry, so a view cannot spell either
/// differently from the rest of the app.
extension AppStorage {
    init(_ key: SettingKey<Bool>) where Value == Bool {
        self.init(wrappedValue: key.defaultValue, key.name)
    }

    init(_ key: SettingKey<Int>) where Value == Int {
        self.init(wrappedValue: key.defaultValue, key.name)
    }

    init(_ key: SettingKey<String>) where Value == String {
        self.init(wrappedValue: key.defaultValue, key.name)
    }
}

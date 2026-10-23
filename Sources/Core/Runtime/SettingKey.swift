// SPDX-License-Identifier: MIT
import Foundation

/// A value `UserDefaults` stores directly. Each type reads itself back strictly: a key holding another type reads as
/// unset, so a hand-edited preference or an older build's value cannot turn into a surprising one.
public protocol SettingValue: Sendable {
    static func read(from defaults: UserDefaults, name: String) -> Self?
    func write(to defaults: UserDefaults, name: String)
}

extension Bool: SettingValue {
    public static func read(from defaults: UserDefaults, name: String) -> Bool? {
        defaults.object(forKey: name) as? Bool
    }

    public func write(to defaults: UserDefaults, name: String) {
        defaults.set(self, forKey: name)
    }
}

extension Int: SettingValue {
    public static func read(from defaults: UserDefaults, name: String) -> Int? {
        guard let number = defaults.object(forKey: name) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: number)
    }

    public func write(to defaults: UserDefaults, name: String) {
        defaults.set(self, forKey: name)
    }
}

extension String: SettingValue {
    public static func read(from defaults: UserDefaults, name: String) -> String? {
        defaults.object(forKey: name) as? String
    }

    public func write(to defaults: UserDefaults, name: String) {
        defaults.set(self, forKey: name)
    }
}

/// One preference: its name in `UserDefaults` and the value it has until the person changes it. The default lives
/// here and nowhere else, so the Settings window, a background reader and the settings export cannot disagree about it
/// (retention was spelled out in three places, the card size in four). `Setting` lists every key.
public struct SettingKey<Value: SettingValue>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

public extension UserDefaults {
    /// The stored value, or the key's default when nothing (or something of another type) is stored. This is how a
    /// reader outside SwiftUI gets the default that `@AppStorage` supplies: nothing needs registering.
    func value<Value: SettingValue>(for key: SettingKey<Value>) -> Value {
        Value.read(from: self, name: key.name) ?? key.defaultValue
    }

    func set<Value: SettingValue>(_ value: Value, for key: SettingKey<Value>) {
        value.write(to: self, name: key.name)
    }

    /// Whether the person (or an import) has stored a value, as opposed to the key resting on its default.
    func hasValue(for key: SettingKey<some SettingValue>) -> Bool {
        object(forKey: key.name) != nil
    }

    func removeValue(for key: SettingKey<some SettingValue>) {
        removeObject(forKey: key.name)
    }
}

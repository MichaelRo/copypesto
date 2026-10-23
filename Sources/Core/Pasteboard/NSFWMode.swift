// SPDX-License-Identifier: MIT
import Foundation

public enum NSFWMode: String, CaseIterable, Sendable {
    case blur
    case hide
    case show

    public static let defaultsKey = Setting.nsfwMode.name
    private static let legacyKey = "nsfwFilterEnabled"

    public var detectsContent: Bool {
        self != .show
    }

    public var blursCards: Bool {
        self != .show
    }

    public var hidesFromGrid: Bool {
        self == .hide
    }

    public static func current(from store: UserDefaults = AppDefaults.store) -> NSFWMode {
        store.string(forKey: defaultsKey).flatMap(NSFWMode.init(rawValue:)) ?? .blur
    }

    /// The old on/off switch meant "hide flagged items"; only an explicit off maps to show.
    public static func migrateLegacySetting(in store: UserDefaults = AppDefaults.store) {
        guard store.string(forKey: defaultsKey) == nil, let legacy = store.object(forKey: legacyKey) as? Bool else {
            return
        }
        store.set((legacy ? NSFWMode.blur : .show).rawValue, forKey: defaultsKey)
    }
}

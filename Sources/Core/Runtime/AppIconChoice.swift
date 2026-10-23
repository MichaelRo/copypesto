// SPDX-License-Identifier: MIT
import Foundation

/// The app icon the person picked in Settings → Appearance. Basil is the icon in the app bundle; the others replace
/// it in the Dock and the app switcher while Pesto has a window open. The Finder icon never changes: writing a custom
/// icon into the installed app breaks its code signature (ADR 0013). Each icon is named after the theme it goes with
/// and listed in the themes' order (Basil, Parmesan, Pine nut, Mortar), so the picker lines each icon up under its
/// theme (ADR 0013).
public enum AppIconChoice: String, CaseIterable, Sendable {
    case basil
    case parmesan
    case pineNut
    case mortar

    public init(stored: String) {
        self = Self(rawValue: stored) ?? Self.legacyNames[stored] ?? .basil
    }

    /// What older versions stored, before the icons took their theme's name: Gold went with Parmesan and Garlic with
    /// Pine nut.
    private static let legacyNames: [String: AppIconChoice] = ["gold": .parmesan, "garlic": .pineNut]

    /// Every value a settings file may carry for the icon: today's names and the older ones.
    public static let acceptedStoredValues = Set(allCases.map(\.rawValue)).union(legacyNames.keys)

    public var displayName: String {
        switch self {
        case .basil: "Basil"
        case .parmesan: "Parmesan"
        case .pineNut: "Pine nut"
        case .mortar: "Mortar"
        }
    }

    public var previewImageName: String {
        switch self {
        case .basil: "AppIconBasil"
        case .parmesan: "AppIconParmesan"
        case .pineNut: "AppIconPineNut"
        case .mortar: "AppIconMortar"
        }
    }

    /// The asset that replaces the bundle icon, or nil to keep it.
    public var dockImageName: String? {
        self == .basil ? nil : previewImageName
    }
}

// SPDX-License-Identifier: MIT
import Foundation

/// What the iOS app keeps ready for its Recent Clips widget (ADR 0052), sealed in the app group: the newest clips that
/// may be shown outside Pesto, and the theme's colors, which the widget cannot read from the app's settings.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Theme: Codable, Equatable, Sendable {
        public let lightGround: String
        public let darkGround: String
        public let lightAccent: String
        public let darkAccent: String

        public init(lightGround: String, darkGround: String, lightAccent: String, darkAccent: String) {
            self.lightGround = lightGround
            self.darkGround = darkGround
            self.lightAccent = lightAccent
            self.darkAccent = darkAccent
        }

        public func ground(dark: Bool) -> String {
            dark ? darkGround : lightGround
        }

        public func accent(dark: Bool) -> String {
            dark ? darkAccent : lightAccent
        }
    }

    public let createdAt: Date
    public let theme: Theme
    /// The newest clips, pinned or not.
    public let clips: [WidgetClip]
    /// The newest pinned clips, for a widget set to show Pinned.
    public let pinned: [WidgetClip]

    /// The History Lock is on and the person keeps clips off the Home Screen while it is: the widget says Locked.
    public let isLocked: Bool
    /// The Mac is covering clip contents (Hide Clip Contents, or a screen share it detected): the widget says so and
    /// holds no clip (ADR 0059). iOS never writes it.
    public let isHidden: Bool

    public init(
        createdAt: Date, theme: Theme, clips: [WidgetClip], pinned: [WidgetClip] = [], isLocked: Bool = false,
        isHidden: Bool = false
    ) {
        self.createdAt = createdAt
        self.theme = theme
        self.clips = clips
        self.pinned = pinned
        self.isLocked = isLocked
        self.isHidden = isHidden
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        theme = try values.decode(Theme.self, forKey: .theme)
        clips = try values.decode([WidgetClip].self, forKey: .clips)
        pinned = try values.decode([WidgetClip].self, forKey: .pinned)
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        isHidden = try values.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    public func clips(from source: WidgetClipSource) -> [WidgetClip] {
        switch source {
        case .recent: clips
        case .pinned: pinned
        }
    }

    /// The clip with this id in either list.
    public func clip(id: UUID) -> WidgetClip? {
        clips.first { $0.id == id } ?? pinned.first { $0.id == id }
    }

    public static func locked(theme: Theme, at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(createdAt: date, theme: theme, clips: [], isLocked: true)
    }

    public static func hidden(theme: Theme, at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(createdAt: date, theme: theme, clips: [], isHidden: true)
    }

    public static func empty(theme: Theme, at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(createdAt: date, theme: theme, clips: [])
    }
}

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
    public let clips: [WidgetClip]

    public init(createdAt: Date, theme: Theme, clips: [WidgetClip]) {
        self.createdAt = createdAt
        self.theme = theme
        self.clips = clips
    }

    public static func empty(theme: Theme, at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(createdAt: date, theme: theme, clips: [])
    }
}

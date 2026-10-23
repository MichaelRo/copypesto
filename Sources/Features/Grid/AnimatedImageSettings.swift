// SPDX-License-Identifier: MIT
import Accessibility
import AppKit
import PestoCore

enum AnimatedImageSettings {
    /// The user's Auto-Play Animated Images setting and Reduce Motion, read live.
    @MainActor
    static var autoPlayAllowed: Bool {
        AnimatedImagePlayback.autoPlayAllowed(
            systemAnimatedImages: AccessibilitySettings.animatedImagesEnabled, reduceMotion: Motion.reduceMotion
        )
    }

    static let changes: [Notification.Name] = [
        AccessibilitySettings.animatedImagesEnabledDidChangeNotification,
        NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
    ]
}

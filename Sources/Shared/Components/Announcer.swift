// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Speaks a message through VoiceOver (and shows nothing on screen). Everything transient in Pesto (a toast, an error
/// banner, a result panel) goes through here so a person who cannot see it still hears it. Tests replace `speak`.
@MainActor
enum Announcer {
    /// An error interrupts what VoiceOver is saying; a count or a confirmation waits its turn.
    enum Priority {
        case normal
        case high
    }

    static var speak: (String, Priority) -> Void = { message, priority in
        var text = AttributedString(message)
        text.accessibilitySpeechAnnouncementPriority = priority == .high ? .high : .default
        AccessibilityNotification.Announcement(text).post()
    }

    static func announce(_ message: String, priority: Priority = .normal) {
        speak(message, priority)
    }
}

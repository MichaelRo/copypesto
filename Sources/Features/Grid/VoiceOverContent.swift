// SPDX-License-Identifier: MIT
import SwiftUI

/// What the hover card shows, for the VoiceOver "More Content" rotor: the card is a window that keyboard focus never
/// enters, so the focused clip carries it. An empty entry adds nothing.
struct VoiceOverDetails {
    var details = ""
    var text = ""
    var title = ""
    var note = ""
    var files = ""
    var inPicture = ""
}

extension View {
    func voiceOverContent(_ content: VoiceOverDetails) -> some View {
        accessibilityCustomContent(AccessibilityCustomContentKey("Details"), content.details, importance: .high)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Text"), content.text)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Title"), content.title)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Note"), content.note)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Files"), content.files)
            .accessibilityCustomContent(AccessibilityCustomContentKey("Text in the picture"), content.inPicture)
    }
}

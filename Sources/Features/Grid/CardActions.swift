// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftUI

/// What a card can ask the shelf to do. The shelf builds one value for all its cards and puts it in the environment;
/// each action takes the clip it is about. An action that is absent hides its menu command, so a card with none (a
/// preview, a snapshot, the sample strip) is a plain card, and the small menu at the cursor supplies only a click.
struct CardActions {
    var detailDismissed: (@MainActor () -> Void)?
    var pointerEntered: (@MainActor () -> Void)?
    var click: (@MainActor (ClipboardItem, ShelfClick) -> Void)?
    var aiAction: (@MainActor (ClipboardItem, AIAction) -> Void)?
    /// Marks a clip sensitive or not.
    var toggleSensitive: (@MainActor (ClipboardItem) -> Void)?
    /// Sets or clears a clip's expiry; `nil` removes it.
    var setExpiry: (@MainActor (ClipboardItem, Date?) -> Void)?
    var quickLook: (@MainActor (ClipboardItem) -> Void)?
    /// Asks the person to authenticate inside the shelf; nil falls back to the system dialog.
    var authenticate: (@MainActor (String) async -> Bool)?
    var pasteAs: (@MainActor (ClipboardItem, TextTransform) -> Void)?
    /// Writes the transformed text to the pasteboard without closing the shelf or pasting.
    var copyTransformed: (@MainActor (ClipboardItem, TextTransform) -> Void)?
    /// An entity quick action (Call, Compose Email, Open in Maps).
    var entityAction: (@MainActor (EntityDetector.Entity) -> Void)?
    /// A drag gesture began on this card.
    var dragStarted: (@MainActor (ClipboardItem) -> Void)?
    /// Picks a pinned hotkey slot (1 to 9), or `nil` to clear it.
    var assignHotkey: (@MainActor (ClipboardItem, Int?) -> Void)?
    var togglePin: (@MainActor (ClipboardItem) -> Void)?
    /// Writes the clip to the pasteboard without pasting or closing the shelf.
    var copy: (@MainActor (ClipboardItem) -> Void)?
    /// Copy As on a colour clip or URL title: puts this text on the clipboard.
    var copyText: (@MainActor (ClipboardItem, String) -> Void)?
    /// Writes raw image data to the pasteboard.
    var copyImageData: (@MainActor (ClipboardItem, Data) -> Void)?
    /// Writes an image (e.g. URL preview image) to the pasteboard.
    var copyImage: (@MainActor (ClipboardItem, NSImage) -> Void)?
    /// Save Image on a picture: writes it to the Downloads folder.
    var saveImage: (@MainActor (ClipboardItem) -> Void)?
    /// Moves a clip to a collection; `nil` takes it out of all of them.
    var moveToCollection: (@MainActor (ClipboardItem, UUID?) -> Void)?
    /// Asks to delete. The shelf shows the confirmation, so every path to a delete shares one alert.
    var delete: (@MainActor (ClipboardItem) -> Void)?
    /// A hidden clip was shown or hidden again, so the keyboard and the card agree.
    var revealChanged: (@MainActor (ClipboardItem, Bool) -> Void)?
}

extension EnvironmentValues {
    @Entry var cardActions = CardActions()
}

// SPDX-License-Identifier: MIT
import Observation
import SwiftUI

/// The colour the focused card's source app washes over the shelf. Held apart from the root views so that a focus move
/// invalidates only the background that draws it: kept as the root's `@State`, every arrow press that changed the
/// colour
/// re-ran the whole overlay.
@Observable
@MainActor
final class ShelfGlow {
    var color: Color = .clear

    func focusChanged(to newColor: Color) {
        if color != newColor { color = newColor }
    }
}

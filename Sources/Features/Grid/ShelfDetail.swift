// SPDX-License-Identifier: MIT
import Observation

/// Whether the row draws placeholders instead of cards (`SwitchQualityPolicy`). Held apart from the grid's `@State` so
/// only
/// the code that builds the cards reads it.
@Observable
@MainActor
final class ShelfDetail {
    var isLight = false
}

// SPDX-License-Identifier: MIT
import Observation
import PestoCore

/// What the keyboard's view draws: the menu, the word before the caret it searches with (ADR 0062) and whether iOS
/// wants the keyboard's own switch key.
@MainActor
@Observable
final class KeyboardModel {
    var menu = KeyboardMenu(hasFullAccess: false) { nil }
    var showsGlobeKey = true
    var word: String?
    /// A word the person took off with its chip, or one already replaced, so it does not search again.
    var dismissedWord: String?
}

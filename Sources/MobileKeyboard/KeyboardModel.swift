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
}

// SPDX-License-Identifier: MIT
import Observation
import PestoCore

/// What the keyboard's view draws: the menu and whether iOS wants the keyboard's own switch key.
@MainActor
@Observable
final class KeyboardModel {
    var menu = KeyboardMenu(hasFullAccess: false) { nil }
    var showsGlobeKey = true
}

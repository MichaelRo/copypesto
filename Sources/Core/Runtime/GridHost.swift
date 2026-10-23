// SPDX-License-Identifier: MIT

/// Which window a grid is in. The floating window builds its grid with `copyOnly` (auto-paste off) or
/// `pasteImmediately`
/// (auto-paste on, the default); the shelf builds it with neither. Whose visibility, keys and Escape apply follows the
/// window, not what a tap does: with auto-paste on, the pinned grid once watched the shelf's flag, so its keyboard,
/// hover detail and Escape never worked.
public enum GridHost: Equatable, Sendable {
    case shelf
    case pinnedWindow

    public init(copyOnly: Bool, pasteImmediately: Bool) {
        self = copyOnly || pasteImmediately ? .pinnedWindow : .shelf
    }
}

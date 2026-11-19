// SPDX-License-Identifier: MIT

/// What a key does to the field being typed in, set by the view controller that owns the text document proxy.
@MainActor
struct KeyboardKeys {
    let insert: (String) -> Void
    let deleteBackward: () -> Void
}

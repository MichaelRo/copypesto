// SPDX-License-Identifier: MIT
import Foundation

/// What the toast says when Pesto has copied a clip but cannot press ⌘V itself. Without Accessibility the bare line
/// "Press ⌘V to paste" never says why; the first time it appears in a launch it says so and offers the fix. A person
/// who
/// chose to go without auto-paste is not told again (ADR 0009: a decline is remembered).
public enum ManualPasteToast: Equatable, Sendable {
    case pressCommandV
    case autoPasteIsOff

    public static func choose(accessibilityTrusted: Bool, declinedAutoPaste: Bool, alreadyExplained: Bool) -> Self {
        !accessibilityTrusted && !declinedAutoPaste && !alreadyExplained ? .autoPasteIsOff : .pressCommandV
    }

    /// The variant that points at a setting can be clicked, and stays on screen long enough to read and click. The same
    /// route is in the menu bar (Grant Accessibility Access…) for a person who cannot click a toast that fades.
    public var isClickable: Bool {
        self == .autoPasteIsOff
    }

    public var visibleSeconds: Double {
        isClickable ? 10 : 2.6
    }
}

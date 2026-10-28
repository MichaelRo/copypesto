// SPDX-License-Identifier: MIT
public struct OnboardingProgress: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case active
        case done
        case skipped
    }

    public var accessibilityGranted: Bool
    public var keyReady: Bool
    public var accessibilitySkipped: Bool
    /// The first step is finished: the person has seen the shortcut and the encryption key exists.
    public var shelfIntroduced: Bool
    /// The person has been through the second step: they chose to go without auto-paste, or saw that it is on and
    /// continued. A permission that was already granted does not skip the step.
    public var pastingConfirmed: Bool

    public init(
        accessibilityGranted: Bool, keyReady: Bool, accessibilitySkipped: Bool, shelfIntroduced: Bool = false,
        pastingConfirmed: Bool = false
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.keyReady = keyReady
        self.accessibilitySkipped = accessibilitySkipped
        self.shelfIntroduced = shelfIntroduced
        self.pastingConfirmed = pastingConfirmed
    }

    public var accessibilityStep: Step {
        if accessibilityGranted { return .done }
        return accessibilitySkipped ? .skipped : .active
    }

    public var keyStep: Step {
        keyReady ? .done : .active
    }

    /// Accessibility only enables auto-paste; without it Pesto still copies and asks for ⌘V.
    public var isComplete: Bool {
        keyReady && (accessibilityGranted || accessibilitySkipped)
    }

    public enum Screen: Int, Equatable, Sendable, CaseIterable {
        case shelf = 1
        case pasting
        case lock
    }

    public static let stepCount = Screen.allCases.count

    /// Three named steps: open the shelf (which also creates the encryption key), allow pasting, then the optional
    /// lock and the last choices.
    public var screen: Screen {
        if !shelfIntroduced || !keyReady { return .shelf }
        return pastingConfirmed ? .lock : .pasting
    }

    public var canStepBack: Bool {
        screen != .shelf
    }

    /// Back is a step in the flow, not an undo: the key stays created, and the earlier screen shows again.
    public mutating func stepBack() {
        switch screen {
        case .shelf: break
        case .pasting: shelfIntroduced = false
        case .lock: pastingConfirmed = false
        }
    }

    public var offersSkip: Bool {
        accessibilityStep == .active
    }
}

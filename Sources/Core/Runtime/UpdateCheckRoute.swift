// SPDX-License-Identifier: MIT
import Foundation

/// A development build never starts Sparkle (`BuildKind`), and Sparkle answers a check on an updater that was not
/// started with a log line only, so the menu item would look broken.
public enum UpdateCheckRoute: Equatable, Sendable {
    case sparkle
    case explainUnavailable

    public static func choose(isDevelopment: Bool) -> Self {
        isDevelopment ? .explainUnavailable : .sparkle
    }
}

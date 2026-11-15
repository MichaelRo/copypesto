// SPDX-License-Identifier: MIT
import Foundation

public enum QuickInsertError: Error, Equatable, Sendable {
    /// No set has been written: the feature is off, or the app has not run since it was turned on.
    case missing
    /// The app group container is missing (an unsigned build, or a device without the group).
    case unavailable
    /// The shared key is not in the Keychain, or the Keychain would not give it.
    case noKey
    /// Sealed with another key, or changed after it was sealed.
    case wrongKey
    case damaged
    case tooLarge
}

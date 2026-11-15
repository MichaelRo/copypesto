// SPDX-License-Identifier: MIT
import Foundation

public enum InboxError: Error, Equatable, Sendable {
    /// Pesto has not run on this device yet, so there is no key to seal to.
    case noKey
    /// The app group container is missing (an unsigned build, or a device without the group).
    case unavailable
    case full
    case tooLarge
    case unsupported
    /// Sealed to another key, or changed after it was sealed.
    case wrongKey
    case damaged
}

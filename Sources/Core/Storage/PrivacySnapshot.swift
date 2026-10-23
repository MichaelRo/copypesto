// SPDX-License-Identifier: MIT
import Foundation

/// What the privacy dashboard shows about the history: numbers only.
public struct PrivacySnapshot: Sendable, Equatable {
    public let clipCount: Int
    public let pinnedCount: Int
    public let maskedSecretCount: Int
    public let oldest: Date?

    public init(clipCount: Int, pinnedCount: Int, maskedSecretCount: Int, oldest: Date?) {
        self.clipCount = clipCount
        self.pinnedCount = pinnedCount
        self.maskedSecretCount = maskedSecretCount
        self.oldest = oldest
    }
}

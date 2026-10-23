// SPDX-License-Identifier: MIT
public struct SharingStateTracker: Sendable {
    private var last = false

    public init() {}

    /// The new state when it differs from the previous reading, otherwise nil. Starts as "not sharing".
    public mutating func update(_ sharing: Bool) -> Bool? {
        guard sharing != last else { return nil }
        last = sharing
        return sharing
    }
}

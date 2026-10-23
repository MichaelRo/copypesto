// SPDX-License-Identifier: MIT
public enum SyncAvailability {
    /// Flip only when sync works end to end: the store schema is CloudKit-compatible, the blob key is
    /// shared between devices, and reconciliation has production callers.
    public static let isAvailable = false
}

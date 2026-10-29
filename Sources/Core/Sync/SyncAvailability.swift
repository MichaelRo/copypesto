// SPDX-License-Identifier: MIT
public enum SyncAvailability {
    /// Flip only when sync works end to end on two Macs (ADR 0018): the folder service writes and reads, merging
    /// converges, the keys are in place and Settings shows the real state.
    public static let isAvailable = false
}

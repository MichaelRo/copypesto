// SPDX-License-Identifier: MIT
import Foundation

/// What the undo stack is willing to hold (ADR 0008). The limits keep the stack's memory small and its restore on the
/// history store's incremental path; the exclusions keep what is meant to expire or stay hidden from outliving that.
public enum UndoPolicy {
    public static let maxEntries = 20
    public static let maxHeldBytes = 16 * 1024 * 1024
    /// A clip bigger than this is deleted for good. Judged from the plain `byteSize` column, so a large clip's file is
    /// never read to find out.
    public static let maxClipBytes = 4 * 1024 * 1024
    /// `HistoryStore` applies a change of up to this many clips in place; a larger one reloads the whole history.
    public static let maxClipsPerEntry = 200

    /// Whether a clip's deletion can be undone: not one that expires on its own (burn after paste, a kept
    /// password-manager copy), not a credential, and not one still being analyzed.
    public static func canHold(
        byteSize: Int, expiresAt: Date?, sensitivityRaw: String?, analysisPending: Bool
    )
    -> Bool {
        byteSize <= maxClipBytes && expiresAt == nil && !analysisPending
            && sensitivityRaw != SensitivityCategory.credential.rawValue
    }

    public static func canHold(clipCount: Int) -> Bool {
        (1...maxClipsPerEntry).contains(clipCount)
    }

    /// Whether deleting these clips together can be undone: every one of them is holdable and there are not too many.
    public static func canHold(_ items: [ClipboardItem]) -> Bool {
        canHold(clipCount: items.count) && items.allSatisfy {
            canHold(
                byteSize: $0.byteSize, expiresAt: $0.expiresAt, sensitivityRaw: $0.sensitivityRaw,
                analysisPending: $0.analysisPending
            )
        }
    }
}

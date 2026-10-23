// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

enum RetentionCaption {
    static func text(for policy: RetentionPolicy) -> String {
        let clips = CountText.clips(policy.maxItemCount)
        let size = ByteCountFormatter.string(fromByteCount: Int64(policy.maxTotalBytes), countStyle: .memory)
        let pinned = String(localized: "Pinned clips are always kept.")
        guard policy.maxAge.isFinite else {
            return String(localized: "Pesto keeps up to \(clips) or \(size), whichever is reached first.") + " " +
                pinned
        }
        let days = String(localized: "\(Int(policy.maxAge / 86_400)) days")
        let limits =
            String(localized: "Pesto keeps clips for \(days), up to \(clips) or \(size), whichever is reached first.")
        return limits + " " + pinned
    }
}

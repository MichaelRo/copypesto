// SPDX-License-Identifier: MIT
import Foundation

/// Whether the shelf blurs clip contents so a screen share, a recording or a person looking over a shoulder does not
/// see them. A share the detector sees counts only with "Hide contents during screen sharing" on; Hide Contents Now
/// (the menu item, an intent or a Focus filter) covers the cards on its own: the person asked for it (ADR 0003).
public enum ContentCover {
    public static func isCovered(manual: Bool, settingOn: Bool, shareDetected: Bool) -> Bool {
        manual || (settingOn && shareDetected)
    }
}

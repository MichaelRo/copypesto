// SPDX-License-Identifier: MIT
import Foundation

/// The explanation under the content-filtering picker, which has to be honest about what this Mac can do.
public enum ContentFilterNotice {
    public static func text(pictureScreeningAvailable: Bool) -> String {
        let modes = "Blur covers a flagged clip until you choose Show on it; Hide keeps it off the shelf (search can "
            + "still find it); Show turns the checks off. Nothing leaves your device."
        if pictureScreeningAvailable {
            return "Links are checked by their address and page title. Pictures, and the pictures on linked pages, "
                + "are screened by your Mac\u{2019}s on-device model. It is best-effort, so right-click any clip and "
                + "choose Mark as Sensitive to blur one yourself. " + modes
        }
        return "This Mac cannot screen pictures (it needs Apple Intelligence on macOS 27), so only links are filtered: "
            + "by their address and page title. Right-click any picture and choose Mark as Sensitive to blur it "
            + "yourself. " + modes
    }
}

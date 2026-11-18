// SPDX-License-Identifier: MIT
#if os(macOS)
import AppKit
#else
import Foundation
#endif

public enum PasteboardProtection {
    public static let concealedMarker = "org.nspasteboard.ConcealedType"

    public static func isProtected(types: [String]) -> Bool {
        types.contains(where: ExclusionRules.concealedTypeMarkers.contains)
    }
}

#if os(macOS)
public extension PasteboardProtection {
    /// Starts a pasteboard write. A protected write stays on this Mac and carries the concealed marker, so it stays off
    /// Universal Clipboard and out of other clipboard managers, which honour the marker as Pesto does when it captures.
    static func beginWrite(on pb: NSPasteboard, protected: Bool) {
        guard protected else {
            pb.clearContents()
            return
        }
        pb.prepareForNewContents(with: [.currentHostOnly])
        pb.setData(Data(), forType: NSPasteboard.PasteboardType(concealedMarker))
    }
}
#endif

// SPDX-License-Identifier: MIT
import CoreGraphics

/// Which display Pesto's own windows (the shelf, the toast, the stack HUD, the floating window, an AI answer) appear
/// on.
/// One rule for all of them: the display of the app being pasted into, because that is where the person is looking.
/// Without a window to go by, the display under the pointer; without that, the first one.
public enum TargetScreenChoice {
    /// The index into `screenFrames` of the display to use, in Cocoa coordinates throughout.
    public static func index(windowCenter: CGPoint?, pointer: CGPoint, screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        if let windowCenter, let index = screenFrames.firstIndex(where: { $0.contains(windowCenter) }) { return index }
        return screenFrames.firstIndex { $0.contains(pointer) } ?? 0
    }
}

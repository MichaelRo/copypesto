// SPDX-License-Identifier: MIT
import CoreGraphics

public enum FloatingWindowPlacement {
    /// The floating window keeps its size and its place on a display, but opens on the display of the app being worked
    /// in:
    /// a frame saved on another display moves across with the same offset from that display's corner.
    public static func frame(saved: CGRect, displays: [CGRect], target: CGRect) -> CGRect {
        guard let home = displays.max(by: { overlap($0, saved) < overlap($1, saved) }), overlap(home, saved) > 0 else {
            return fit(saved, in: target)
        }
        if home == target { return fit(saved, in: target) }
        let moved = saved.offsetBy(dx: target.minX - home.minX, dy: target.minY - home.minY)
        return fit(moved, in: target)
    }

    /// The frame moved (and cut, if it is larger) so that it lies inside `area`.
    public static func fit(_ frame: CGRect, in area: CGRect) -> CGRect {
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        let x = min(max(frame.minX, area.minX), area.maxX - width)
        let y = min(max(frame.minY, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }
}

// SPDX-License-Identifier: MIT

/// The screenshot tools whose pictures are screen captures (ADR 0080): their words run to the edges, so they are
/// cropped less. Matched by the source app's bundle identifier only; a capture pasted from elsewhere is a picture.
public enum ScreenCaptureApps {
    public static let bundleIDs: Set<String> = [
        "com.apple.screencaptureui",
        "com.apple.Screenshot",
        "pl.maketheweb.cleanshotx",
        "cc.ffitch.shottr"
    ]

    public static func isCapture(sourceBundleID: String?) -> Bool {
        sourceBundleID.map(bundleIDs.contains) ?? false
    }
}

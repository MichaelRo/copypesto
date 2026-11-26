// SPDX-License-Identifier: MIT
import Foundation

/// The icons a sealed set carries for the apps of the clips it lists: each app once, in the order its clips come, a
/// PNG of at most `maxIconBytes` (the size sync's app catalog allows), within a count and a byte cap of its own.
public enum SourceAppIcons {
    public static let maxIconBytes = 8 * 1024
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    public static func isIcon(_ data: Data) -> Bool {
        !data.isEmpty && data.count <= maxIconBytes && data.starts(with: pngSignature)
    }

    public static func collect(
        for bundleIDs: some Sequence<String?>, maxApps: Int, maxBytes: Int, icon: (String) -> Data?
    )
    -> [String: Data] {
        var icons: [String: Data] = [:]
        var seen: Set<String> = []
        var bytes = 0
        for case let bundleID? in bundleIDs where icons.count < maxApps {
            guard seen.insert(bundleID).inserted, let data = icon(bundleID), isIcon(data),
                  bytes + data.count <= maxBytes else { continue }
            icons[bundleID] = data
            bytes += data.count
        }
        return icons
    }
}

// SPDX-License-Identifier: MIT
#if os(macOS)
import AppKit

/// Source-app icons resolved by bundle ID and shared by every card, instead of a PNG copied onto each history item.
@MainActor
public final class SourceIconCache {
    public static let shared = SourceIconCache()

    private var records: [String: SourceAppRecord] = [:]
    private var images: [String: NSImage] = [:]
    /// How many icons this cache has drawn, which a test reads to show that an app is drawn once.
    private(set) var drawCount = 0

    public init() {}

    public func image(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = images[bundleID] { return cached }
        guard let image = NSImage(data: record(for: bundleID).iconData) else { return nil }
        images[bundleID] = image
        return image
    }

    /// The app's icon to hand to another surface (the widget), or nil for an app this Mac cannot find, whose record
    /// holds the disk's icon in its place.
    public func pngData(forBundleID bundleID: String?) -> Data? {
        guard let bundleID else { return nil }
        let record = record(for: bundleID)
        guard record.displayName != SourceAppRecord.unknownDisplayName, !record.iconData.isEmpty else { return nil }
        return record.iconData
    }

    public func displayName(forBundleID bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        return record(for: bundleID).displayName
    }

    /// The app's record, drawn on the first ask. The ingest path (`SourceAppResolver`) and the cards both come here.
    func record(for bundleID: String) -> SourceAppRecord {
        if let cached = records[bundleID] { return cached }
        drawCount += 1
        let record = SourceAppResolver.computeRecord(bundleID: bundleID)
        records[bundleID] = record
        return record
    }
}
#endif

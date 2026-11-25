// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct ItemFootLineView: View {
    let item: ClipboardItem
    var onPicture = false
    var ink: Color?
    var showsGIF = false
    var showsTitleOnFace = false
    var trailingMark: String?
    @Environment(\.clipRevision) private var revision
    @Environment(\.cardClock) private var clock
    @Environment(\.peerDeviceNames) private var peerDeviceNames
    @Environment(\.sourceAppCatalog) private var sourceApps

    var body: some View {
        CardFootLineView(
            line: CardFootLineView.line(
                for: item, now: clock ?? .now, device: CardFootLineView.device,
                showsTitleOnFace: showsTitleOnFace, peerDeviceNames: peerDeviceNames
            ),
            isPinned: revision?.isPinned ?? item.isPinned,
            inCollection: (revision.map(\.collectionID) ?? item.collectionID) != nil,
            onPicture: onPicture,
            ink: ink,
            showsGIF: showsGIF,
            trailingMark: trailingMark,
            appIcon: item.isRemote ? nil : sourceApps?.entry(for: item.sourceBundleID).flatMap(Self.icon)
        )
    }
}

extension ItemFootLineView {
    @MainActor private static let icons = NSCache<NSString, UIImage>()

    /// An app's icon, decoded once per app and icon.
    @MainActor
    static func icon(_ entry: SyncAppCatalog.Entry) -> UIImage? {
        let key = "\(entry.bundleID)#\(entry.icon.hashValue)" as NSString
        if let cached = icons.object(forKey: key) { return cached }
        guard let image = UIImage(data: entry.icon) else { return nil }
        icons.setObject(image, forKey: key)
        return image
    }
}

extension CardFootLineView {
    static func line(
        for item: ClipboardItem, now: Date, device: CardFootLine.Device, showsTitleOnFace: Bool = false,
        peerDeviceNames: [String: String] = [:]
    )
    -> CardFootLine {
        CardFootLine.make(
            CardFootLine.origin(of: item, peerDeviceNames: peerDeviceNames),
            title: item.customTitle,
            age: CardAge.text(for: item, inCollection: false, now: now),
            device: device,
            showsTitleOnFace: showsTitleOnFace
        )
    }
}

extension EnvironmentValues {
    @Entry var clipRevision: ClipCard.Revision?
    /// The minute the grid last ticked (`LibraryGrid`), so every visible card's age moves together without a timer
    /// each.
    @Entry var cardClock: Date?
    @Entry var peerDeviceNames: [String: String] = [:]
    /// The apps other devices named (ADR 0068); a card shows the app's icon from it.
    @Entry var sourceAppCatalog: SourceAppCatalogStore?
}

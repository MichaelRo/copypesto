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
            trailingMark: trailingMark
        )
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
}

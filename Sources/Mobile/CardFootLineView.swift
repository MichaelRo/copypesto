// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The line of facts at a card's foot: where the clip came from and its age, then its pin and collection. On a picture
/// it sits on a pill of the card's own ground; on a color it is the fill's ink.
struct CardFootLineView: View {
    let item: ClipboardItem
    var onPicture = false
    var ink: Color?
    var showsGIF = false
    var showsTitleOnFace = false
    var trailingMark: String?
    @Environment(\.clipRevision) private var revision
    @Environment(\.cardClock) private var clock

    var body: some View {
        let line = Self.line(for: item, now: clock ?? .now, device: Self.device, showsTitleOnFace: showsTitleOnFace)
        HStack(spacing: 6) {
            lead(line).modifier(PillGround(isOn: onPicture))
            Spacer(minLength: 4)
            if showsGIF {
                Text(verbatim: "GIF").font(.caption2.weight(.semibold)).modifier(PillGround(isOn: onPicture))
            }
            marks.modifier(PillGround(isOn: onPicture && hasMarks))
        }
        .font(.caption)
        .foregroundStyle(ink.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private func lead(_ line: CardFootLine) -> some View {
        HStack(spacing: 4) {
            if let symbol = line.symbol {
                Image(systemName: symbol).imageScale(.small)
            }
            ViewThatFits(in: .horizontal) {
                ForEach(line.texts, id: \.self) { Text($0) }
                Text(verbatim: "")
            }
        }
    }

    private var isPinned: Bool {
        revision?.isPinned ?? item.isPinned
    }

    private var inCollection: Bool {
        (revision.map(\.collectionID) ?? item.collectionID) != nil
    }

    private var hasMarks: Bool {
        isPinned || inCollection || trailingMark != nil
    }

    @ViewBuilder
    private var marks: some View {
        if hasMarks {
            HStack(spacing: 4) {
                if let trailingMark { Text(trailingMark).font(.caption2.weight(.semibold)) }
                if inCollection { Image(systemName: "folder.fill").imageScale(.small) }
                if isPinned { Image(systemName: "pin.fill").imageScale(.small) }
            }
        }
    }

    static func line(
        for item: ClipboardItem, now: Date, device: CardFootLine.Device, showsTitleOnFace: Bool = false
    )
    -> CardFootLine {
        CardFootLine.make(
            CardFootLine.origin(of: item),
            title: item.customTitle,
            age: CardAge.text(for: item, inCollection: false, now: now),
            device: device,
            showsTitleOnFace: showsTitleOnFace
        )
    }

    static let device: CardFootLine.Device = UIDevice.current.userInterfaceIdiom == .pad
        ? .init(name: String(localized: "iPad"), symbol: "ipad")
        : .init(name: String(localized: "iPhone"), symbol: "iphone")
}

private struct PillGround: ViewModifier {
    let isOn: Bool
    @Environment(\.pestoSurface) private var surface

    func body(content: Content) -> some View {
        if isOn {
            content
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(surface.opacity(PictureScrim.pillOpacity), in: .capsule)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    @Entry var clipRevision: ClipCard.Revision?
    /// The minute the grid last ticked (`LibraryGrid`), so every visible card's age moves together without a timer
    /// each.
    @Entry var cardClock: Date?
}

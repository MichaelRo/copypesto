// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The line of facts at a card's foot: where the clip came from and its age, then its pin, collection, or badge.
/// On a picture it sits on a pill of the card's own ground; on a color it is the fill's ink.
struct CardFootLineView: View {
    let line: CardFootLine
    var isPinned = false
    var inCollection = false
    var onPicture = false
    var ink: Color?
    var showsGIF = false
    var trailingMark: String?
    var trailingSymbol: String?
    var onTrailingSymbolTap: (() -> Void)?

    var body: some View {
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

    private var hasMarks: Bool {
        isPinned || inCollection || trailingMark != nil || trailingSymbol != nil
    }

    @ViewBuilder
    private var marks: some View {
        if hasMarks {
            HStack(spacing: 4) {
                if let trailingMark { Text(trailingMark).font(.caption2.weight(.semibold)) }
                if let trailingSymbol {
                    if let onTrailingSymbolTap {
                        Button(action: onTrailingSymbolTap) {
                            Image(systemName: trailingSymbol).imageScale(.small)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: trailingSymbol).imageScale(.small)
                    }
                }
                if inCollection { Image(systemName: "folder.fill").imageScale(.small) }
                if isPinned { Image(systemName: "pin.fill").imageScale(.small) }
            }
        }
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

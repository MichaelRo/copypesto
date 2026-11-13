// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// How the line of facts is drawn on one kind of card. `over` is set on a picture or a color, where the card's own
/// text colors would not read: on a picture everything sits on the pill ground (ADR 0026's contrast rule), on a color
/// it is the fill's own ink.
struct MetaLineStyle {
    var over: HeaderOverlay?
    var onPicture = false
    var showsGIF = false
    var wholeClip = false
}

@MainActor
extension ClipboardCard {
    var metaFacts: CardMetaLine.Facts {
        CardMetaLine.Facts(
            title: item.customTitle,
            source: item.isRemote ? String(localized: "Another device") : item.knownSourceAppName,
            age: timeAgo,
            measure: [footerDetail(withLines: true), footerDetail(withLines: false)].compactMap(\.self),
            isActive: isFocused || isPointed
        )
    }

    /// The one line of facts at the foot of every card (ADR 0044): the shortcut number, where the clip came from, its
    /// age (and its size on the card being looked at), then what the person did to it (expiry, snippet, shortcut, pin,
    /// collection).
    func metaLine(_ style: MetaLineStyle) -> some View {
        var facts = metaFacts
        facts.showsWholeClip = style.wholeClip
        if style.over != nil { facts.measure = [] }
        let texts = CardMetaLine.candidates(facts)
        return VStack(alignment: .leading, spacing: 4) {
            if !item.tags.isEmpty {
                tagChipsRow(onDark: style.onPicture)
            }
            ViewThatFits(in: .horizontal) {
                ForEach(texts, id: \.self) { text in
                    metaRow(text: text, namesCollection: true, style: style)
                }
                metaRow(text: texts.last, namesCollection: false, style: style)
                metaRow(text: nil, namesCollection: false, style: style)
            }
        }
        .environment(\.colorScheme, style.over?.scheme ?? colorScheme)
    }

    private func metaRow(text: String?, namesCollection: Bool, style: MetaLineStyle) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if let number = shortcutNumber {
                if let over = style.over {
                    ContentFirstPill(text: "\u{2318}\(number)", ink: over.ink, onPicture: style.onPicture)
                } else {
                    shortcutKeycap(number)
                }
            }
            sourceLabel(text: text, style: style)
            Spacer(minLength: 4)
            if style.showsGIF, let over = style.over {
                ContentFirstPill(text: "GIF", ink: over.ink, onPicture: style.onPicture)
            }
            if hasStateMarks {
                stateMarks.metaGround(style, surface: surface)
            }
            // On a collection's own shelf every card would carry the same badge.
            if !showsFirstCopyTime, let collectionID = item.collectionID,
               let collection = availableCollections.first(where: { $0.id == collectionID })
            {
                if let over = style.over {
                    contentFirstCollectionBadge(
                        collection, ink: over.ink, onPicture: style.onPicture, showsName: namesCollection
                    )
                } else {
                    collectionBadge(collection, showsName: namesCollection)
                }
            }
            if style.over == nil, let category = item.sensitivity {
                sensitivityBadge(category)
            }
        }
    }

    private func sourceLabel(text: String?, style: MetaLineStyle) -> some View {
        HStack(alignment: .center, spacing: 5) {
            sourceTile
            if let text {
                Text(text)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(style.over
                        .map { AnyShapeStyle($0.ink) } ?? AnyShapeStyle(AdaptiveContrast.quiet(contrast)))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .metaGround(style, surface: surface)
    }

    @ViewBuilder
    private var sourceTile: some View {
        if let customSymbol = item.customSymbolName {
            CollectionIcon(symbolName: customSymbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: CardLayout.sourceTileSize, height: CardLayout.sourceTileSize)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if item.isRemote {
            RemoteSourceTile()
        } else {
            SourceAppIconView(
                bundleID: item.sourceBundleID,
                appName: item.sourceAppName,
                size: CardLayout.sourceTileSize
            )
        }
    }

    private var showsPin: Bool {
        CardMetaLine.showsPin(
            isPinned: item.isPinned, isSnippet: item.isTemplate, hasShortcut: item.pinnedHotkeyIndex != nil
        )
    }

    private var hasStateMarks: Bool {
        item.expiresAt != nil || item.isPinned || item.pinnedHotkeyIndex != nil || suggestedHotkeySlot != nil
    }

    private var stateMarks: some View {
        HStack(alignment: .center, spacing: 5) {
            stateBadges
            if let slot = item.pinnedHotkeyIndex {
                Keycap(symbol: "\u{2303}\(slot)", size: .compact).accessibilityHidden(true)
            } else if let slot = suggestedHotkeySlot {
                Keycap(symbol: "\u{2303}\(slot)", size: .compact, style: .ghost)
                    .accessibilityHidden(true)
                    .animation(Motion.animation(.pestoPop), value: slot)
            }
            if showsPin {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, options: .nonRepeating, value: Motion.reduceMotion ? false : item.isPinned)
            }
        }
    }

    /// The collection badge without the frosted ground the standard card gives it, which no contrast can be promised
    /// for over a picture: the pill ground there, the fill's own ink on a color.
    private func contentFirstCollectionBadge(
        _ collection: CollectionRef, ink: Color, onPicture: Bool, showsName: Bool
    )
    -> some View {
        HStack(spacing: 3) {
            CollectionIcon(symbolName: collection.symbolName)
                .font(.caption2.weight(.medium))
            if showsName {
                Text(collection.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(ink.opacity(PictureScrim.badgeOpacity))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            if onPicture { Capsule().fill(surface.opacity(PictureScrim.pillOpacity)) }
        }
    }
}

private extension View {
    /// On a picture nothing is drawn without the pill ground, which is what keeps 4.5:1 over the brightest one
    /// (`PictureScrimTests`); anywhere else the content stands on the card.
    @ViewBuilder
    func metaGround(_ style: MetaLineStyle, surface: Color) -> some View {
        if style.onPicture {
            padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    surface.opacity(PictureScrim.pillOpacity), in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.32), lineWidth: 1)
                }
        } else {
            self
        }
    }
}

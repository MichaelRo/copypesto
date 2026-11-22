// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// One clip as a Pesto card: the content is the card, one quiet line of facts at its foot. A tap copies (a secret too,
/// without showing it), a long press opens the menu, a drag hands the content to another app unless the card is
/// covered (ADR 0003).
struct ClipCard: View {
    let item: ClipboardItem
    let width: CGFloat
    let collections: [Pinboard]
    var isFocused = false
    var inCollection = false
    var isSelected = false
    var isFlashed = false
    /// A change saved by the storage actor (a pin, a sync) reaches this context's objects without telling the card,
    /// so the grid hands the fields the card draws from as a value; a new value redraws it.
    var revision: Revision?

    @Environment(MobileAppState.self) var appState
    @Environment(LibraryModel.self) var library
    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State var media = CardMediaState()
    @State private var isOnScreen = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CardGridLayout.cornerRadius, style: .continuous)
    }

    var concealment: CardConcealment {
        appState.secretReveal.concealment(for: item)
    }

    var isCoveredForPrivacy: Bool {
        appState.secretReveal.isCoveredForPrivacy(item.id)
    }

    var face: CardFace {
        CardFace.decide(.init(
            type: item.type,
            text: item.type == .text || item.type == .url || item.type == .color ? item.gridPreview : "",
            isConcealed: concealment.isConcealed,
            isSecret: item.sensitivityRaw != nil && !isCoveredForPrivacy,
            pictureAspect: pictureAspect,
            isAnimated: media.picture?.isAnimated ?? false,
            hasLinkPicture: media.linkPicture != nil,
            isDark: colorScheme == .dark
        ))
    }

    private var pictureAspect: Double? {
        if let width = item.pixelWidth, let height = item.pixelHeight, width > 0, height > 0 {
            return Double(width) / Double(height)
        }
        guard let size = media.picture?.image.size, size.height > 0 else { return nil }
        return size.width / size.height
    }

    var body: some View {
        let face = face
        card(face: face, width: width)
            .contentShape(shape)
            .contentShape(.contextMenuPreview, shape)
            .contentShape(.dragPreview, shape)
            .onTapGesture {
                if library.isSelecting {
                    library.toggleSelection(item.id)
                } else {
                    copy()
                }
            }
            .onKeyPress(.return) {
                if library.isSelecting {
                    library.toggleSelection(item.id)
                } else {
                    copy()
                }
                return .handled
            }
            .contextMenu {
                CardMenu(card: self)
            } preview: {
                // The preview is hosted apart from the grid, so an observable the face reads (a covered card reads the
                // app state) has to be handed over, or the long press on a hidden clip traps.
                card(face: face, width: 300).frame(width: 300)
                    .environment(appState)
                    .environment(library)
            }
            .modifier(CardDragSource(card: self))
            .focusedValue(\.clipCommands, isFocused ? commands : nil)
            .task(id: CardMediaState.Key(
                id: item.id,
                isShown: appState.secretReveal.isShown(item.id),
                byteSize: item.byteSize,
                isAnimatedHint: media.isAnimated,
                isConcealed: concealment.isConcealed
            )) {
                await media.load(
                    item, container: appState.historyContainer, isShown: appState.secretReveal.isShown(item.id),
                    fetchPreview: { await appState.loadLinkPreview(for: item) }
                )
            }
            .task(id: AnimationKey(
                plays: isOnScreen && !Motion.reduceMotion && !concealment.isConcealed,
                isAnimated: media.isAnimated,
                byteSize: item.byteSize,
                isLinkAnimated: media.isLinkAnimated
            )) {
                guard isOnScreen, !Motion.reduceMotion, !concealment.isConcealed else { return }
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, isOnScreen else { return }
                let id = item.id
                let byteSize = item.byteSize
                let container = appState.historyContainer
                await media.animate(
                    decode: {
                        await CardMedia.gifFrames(
                            itemID: id, byteSize: byteSize, container: container, budget: .card
                        )
                    },
                    linkDecode: {
                        await CardMedia.linkGIFFrames(for: id, budget: .card)
                    }
                )
            }
            .onAppear { isOnScreen = true }
            .onDisappear {
                isOnScreen = false
                media.dropAnimation()
            }
            .modifier(CardAccessibility(card: self))
            .accessibilityIdentifier(MobileAccessibilityID.clipCard)
    }

    func card(face: CardFace, width: CGFloat) -> some View {
        Color.clear
            .aspectRatio(CardGridLayout.aspectRatio, contentMode: .fit)
            .overlay {
                ClipCardFace(
                    item: item, face: face, media: media, width: width, revision: revision ?? Revision(item),
                    playsAnimation: CardAnimation.plays(
                        isAnimated: media.picture?.animation != nil, isOnScreen: isOnScreen,
                        isConcealed: concealment.isConcealed, reduceMotion: Motion.reduceMotion
                    ),
                    inCollection: inCollection
                )
                .environment(\.clipRevision, revision ?? Revision(item))
            }
            .clipShape(shape)
            .background {
                shape.fill(cardFill)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 4, y: 2)
            }
            .overlay(alignment: .topTrailing) {
                if library.isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? .white : .secondary, isSelected ? accent : .clear)
                        .background(Circle().fill(isSelected ? Color.clear : Color.black.opacity(0.25)))
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .overlay { shape.strokeBorder(borderColor, lineWidth: ringed ? 2 : 0.75) }
            .animation(Motion.animation(.pestoQuick), value: ringed)
    }

    private var ringed: Bool {
        isSelected || isFocused || isFlashed
    }

    private var borderColor: Color {
        if ringed { return accent }
        return Color.primary.opacity(contrast == .increased ? 0.45 : 0.14)
    }

    /// As the Mac's card on a solid shelf: opaque white on a light ground, white at 10 percent on a dark one.
    private var cardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : .white
    }

    private var commands: ClipCommandActions {
        ClipCommandActions(
            isPinned: item.isPinned,
            copy: copy,
            togglePin: togglePin,
            delete: { library.pendingDelete = item.id }
        )
    }

    func copy() {
        Task {
            guard await appState.copyAsync(item) else { return }
            library.didCopy(item.id)
            Announcer.announce(String(localized: "Copied"))
        }
    }

    func togglePin() {
        let id = item.id
        Task { await appState.togglePin(id) }
    }

    func delete() {
        let id = item.id
        Task { await appState.delete([id]) }
    }

    func show() {
        let id = item.id
        if isCoveredForPrivacy { return appState.secretReveal.showUnderCover(id) }
        if item.sensitivityRaw != nil {
            Task { await appState.secretReveal.show(id, reason: String(localized: "Show the hidden clip")) }
            return
        }
        if item.isNSFW {
            appState.secretReveal.showNSFW(id)
        }
    }

    func hide() {
        appState.secretReveal.hide(item.id)
        appState.secretReveal.hideNSFW(item.id)
    }

    func share() {
        guard !concealment.isConcealed, let content = ClipContent.of(item) else { return }
        library.sharing = ClipShare(content)
    }

    private struct AnimationKey: Equatable {
        let plays: Bool
        let isAnimated: Bool
        let byteSize: Int
        let isLinkAnimated: Bool
    }

    struct Revision: Equatable {
        let isPinned: Bool
        let collectionID: UUID?
        let timestamp: Date
        let isCovered: Bool
        let content: String
        let byteSize: Int
        let metadata: Data?

        init(_ item: ClipboardItem) {
            isPinned = item.isPinned
            collectionID = item.collectionID
            timestamp = item.timestamp
            isCovered = item.analysisPending || item.isNSFW
            content = item.contentHash
            byteSize = item.byteSize
            metadata = item.metadataCiphertext
        }
    }
}

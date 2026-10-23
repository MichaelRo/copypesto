// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// swiftlint:disable:next type_body_length
struct ClipboardCard: View {
    @Environment(\.pestoAccent) var accent
    @Environment(\.colorSchemeContrast) var contrast
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.cardActions) var actions
    let item: ClipboardItem
    var isFocused: Bool = false
    var focusAnchor: FocusedCardAnchor?
    var shortcutNumber: Int?
    var revealsDetail: Bool = false
    var detailSuppressed: Bool = false
    var scrollState: ShelfScrollState?
    /// `true` when this card is part of the active multi-select for stack creation.
    var isSelected: Bool = false
    var showRequest: ShowRequest?
    var isFlashing = false
    /// Slots already registered by another process; shown as disabled in the picker.
    var unavailableHotkeySlots: Set<Int> = []
    /// When `true`, card content is blurred (screen-sharing privacy mode is active).
    var isPrivacyBlurred: Bool = false
    /// Available collections for the "Move to Collection" context menu submenu.
    var availableCollections: [CollectionRef] = []
    /// A hidden clip revealed from outside the card (Return on the keyboard-focused card).
    var revealedFromOutside = false
    /// False while the history is locked: a locked shelf must not go out and fetch pages.
    var previewsAllowed = true
    /// Bumped by the shelf when a shown secret must hide: it closed, the history locked or the contents were covered.
    var hideSecretsGeneration = 0
    /// False on a Mac that cannot authenticate: a hidden clip cannot be shown there, so Show is not offered. Pasting it
    /// still writes the real text.
    var canRevealHidden = true

    @AppStorage(Setting.cardSize) var cardSizeRaw: String
    @AppStorage(Setting.cardWidth) var cardWidth: Int

    var cardDimensions: CGSize {
        CardSize.dimensions(sizeRaw: cardSizeRaw, customWidth: cardWidth)
    }

    /// Files of a file clip that are gone, read off the main thread (see `FileClip.missing(inText:)`).
    @State var missingFileCount = 0
    @State var isHovered = false
    @State var thumbnail: NSImage?
    @State var thumbnailIsAnimated = false
    /// The clip's size when `thumbnail` was made (a still that becomes its GIF has another).
    @State var thumbnailByteSize = 0
    @State var urlOGImage: NSImage?
    @State var urlOGImageIsAnimated = false
    @State var urlFavicon: NSImage?
    @State var showDetailPopover = false
    @State var detailSpent = false
    /// The card scrolls, so it takes the pointer and stays open while the pointer crosses to it or is on it.
    @State var detailScrolls = false
    @State var pointerInDetail = false
    @State var detailHeld = false
    @State var graceTask: Task<Void, Never>?
    @State var hoverTask: Task<Void, Never>?
    @State var isRenamingTitle = false
    @State var renameText = ""
    @FocusState var renameFieldFocused: Bool
    @State var showNotePopover = false
    @State var noteText = ""
    @State var showIconPopover = false
    @State var showTagPopover = false
    @State var tagText = ""
    @State var tagToRemove: String?
    @State var showRemoveTagConfirmation = false
    @State var isNSFWRevealed = false
    @State var revealedSecret: String?
    @AppStorage(Setting.nsfwMode) var nsfwModeRaw: String
    @Environment(\.modelContext) var modelContext
    @Environment(\.clipEditor) var clipEditor: ClipEditor?

    private static let cardCornerRadius: CGFloat = 12
    var nsfwMode: NSFWMode {
        NSFWMode(rawValue: nsfwModeRaw) ?? .blur
    }

    var hoverArmed: Bool {
        scrollState?.pointerHasMoved ?? true
    }

    /// The pointer resting where the shelf opened is not a hover: otherwise the card under it lifts, brightens and
    /// plays as if it were the focused one.
    var isPointed: Bool {
        DetailPopoverPolicy.hoverCounts(hovered: isHovered, pointerMoved: hoverArmed)
    }

    private var autoPlayAllowed: Bool {
        scrollState?.autoPlayAllowed ?? AnimatedImageSettings.autoPlayAllowed
    }

    var isScrolling: Bool {
        scrollState?.isScrolling ?? false
    }

    /// A pointer resting while cards slide under it must not lift each one in turn.
    private var isLifted: Bool {
        DetailPopoverPolicy.isLifted(
            hovered: isHovered, pointerMoved: hoverArmed, scrolling: isScrolling, focused: isFocused
        )
    }

    var body: some View {
        let accessibility = accessibility
        return popoverCard
            .modifier(CardClickGestures(
                onClick: actions.click.map { click in { click(item, $0) } },
                isFlashing: isFlashing
            ))
            // On the card itself, not on the body that shows the secret: covering and uncovering swaps the drag
            // branch below, which rebuilds that body, and a hook there hid the text the moment it was shown.
            .onDisappear { hideSecret() }
            .onChange(of: hideSecretsGeneration) { hideSecret() }
            .onChange(of: isPrivacyBlurred) { _, covered in
                if covered {
                    hideSecret()
                    hideAgain()
                }
            }
            // The shelf clears what it revealed when it closes; a card that was shown by its own click must follow.
            .modifier(ShowRequestReceiver(request: showRequest, itemID: item.id, perform: showShortcut))
            .onChange(of: revealedFromOutside) { _, outside in
                if !outside { isNSFWRevealed = false }
            }
            .task(id: CardLoadKey(id: item.id, isPending: item.analysisPending, byteSize: item.byteSize)) {
                await loadThumbnailIfNeeded()
                await loadURLMetadataIfNeeded()
            }
            .task(id: item.displayPreviewText) {
                guard item.type == .file else { return }
                missingFileCount = await FileClip.missing(inText: item.displayPreviewText).count
            }
            .background { if isFocused, let focusAnchor { FocusedCardAnchorView(anchor: focusAnchor) } }
            .contextMenu { cardContextMenu }
            .gatedDrag(allowed: concealment.allowsDrag) {
                closeDetailForGood()
                actions.dragStarted?(item)
                return makeItemProvider()
            }
            // One element per card: without this the icon and badge each surfaced as a duplicate button.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(AccessibilityID.card)
            .accessibilityLabel(accessibility.label)
            .accessibilityValue(revealedSecret.map { "\(accessibility.value), shown: \($0)" } ?? accessibility
                .value)
            .voiceOverContent(isFocused && !isCoveredForPrivacy ? voiceOverContent : VoiceOverDetails())
            .accessibilityHint(hidesItsContent
                ? (canRevealHidden ? "Hidden. Pastes without showing. Use Show to reveal it." : "Hidden.")
                : "Pastes this clip.")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            // The card is a plain `.onTapGesture`, not a `Button`, so nothing answers VoiceOver's own
            // default activation (Return in the rotor, double-tap) without this.
            // Pastes, hidden or not (ADR 0003); Show is its own action.
            .accessibilityAction { actions.click?(item, .activate) }
            .accessibilityAction(named: "Show") {
                guard canRevealHidden else { return }
                if isBlurredAsSensitive || isCoveredForPrivacy {
                    reveal()
                } else if item.sensitivity != nil {
                    toggleReveal()
                }
            }
            .accessibilityAction(named: "Copy") { actions.copy?(item) }
            .accessibilityAction(named: "Quick Look") {
                if item.sensitivity == nil, concealment.allowsQuickLook { actions.quickLook?(item) }
            }
            .accessibilityAction(named: "Delete") { actions.delete?(item) }
            .modifier(moreActions)
            .modifier(CardEditActions(
                rename: {
                    renameText = item.customTitle ?? ""
                    isRenamingTitle = true
                },
                addNote: {
                    noteText = item.userNote ?? ""
                    showNotePopover = true
                },
                addTag: {
                    tagText = ""
                    showTagPopover = true
                }
            ))
    }

    /// The popovers, apart from `body`: one modifier chain this long was more than Xcode 26 would type-check.
    private var popoverCard: some View {
        hoverableCard
            // Anchored here, not to the context-menu buttons: the menu closes when an item is chosen, taking a
            // popover
            // attached to it along.
                .popover(isPresented: $showNotePopover, arrowEdge: .top) {
                    NotePopover(noteText: $noteText) {
                        let trimmed = noteText.trimmingCharacters(in: .whitespaces)
                        edit { $0.userNote = trimmed.isEmpty ? nil : trimmed }
                        showNotePopover = false
                    }
                }
                .popover(isPresented: $showIconPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Clip icon")
                                .font(.headline)
                            Spacer()
                            if item.customSymbolName != nil {
                                Button("Reset") {
                                    edit { $0.customSymbolName = nil }
                                    showIconPopover = false
                                }
                                .buttonStyle(.plain)
                                .pestoQuiet()
                                .font(.caption)
                            }
                        }
                        CollectionIconPicker(selection: Binding(
                            get: { item.customSymbolName ?? "" },
                            set: { newSymbol in
                                edit { $0.customSymbolName = newSymbol.isEmpty ? nil : newSymbol }
                                showIconPopover = false
                            }
                        ))
                    }
                    .padding(12)
                    .frame(width: 280)
                }
                .popover(isPresented: $showTagPopover, arrowEdge: .top) {
                    TagPopover(tagText: $tagText) {
                        let trimmed = tagText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty, !item.tags.contains(trimmed) {
                            edit { clip in
                                var updated = clip.tags
                                updated.append(trimmed)
                                clip.tags = updated
                            }
                        }
                        showTagPopover = false
                    }
                }
    }

    /// Split out of `body` (SwiftUI type-checker perf, same reason as `decoratedCard`): hover and
    /// keyboard-focus both drive the detail popover.
    private var hoverableCard: some View {
        decoratedCard
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            // Keyboard focus reveals the detail too, but only once the user has
            // navigated with the keyboard (`revealsDetail`); an idle shelf must not show it. Hover,
            // the reveal flag and the suppression flag are watched separately so each change
            // restarts the dwell.
            .onChange(of: isHovered) { _, hovering in
                if hovering {
                    actions.pointerEntered?()
                    graceTask?.cancel()
                    detailHeld = false
                } else {
                    detailSpent = false
                    if showDetailPopover, DetailPopoverPolicy.waitsForPointer(contentScrolls: detailScrolls) {
                        startDetailGrace()
                    }
                }
                restartDetailPopoverTimer()
            }
            .onChange(of: detailHeld) { _, _ in restartDetailPopoverTimer() }
            .onChange(of: showDetailPopover) { _, showing in
                guard !showing else { return }
                graceTask?.cancel()
                detailHeld = false
                pointerInDetail = false
                detailScrolls = false
            }
            .onChange(of: hoverArmed) { _, _ in restartDetailPopoverTimer() }
            .onChange(of: scrollState?.menuOpenings) { _, _ in
                // Its own context menu must not open under the popover.
                guard isHovered || showDetailPopover else { return }
                closeDetailForGood()
            }
            .onChange(of: revealsDetail) { _, _ in restartDetailPopoverTimer() }
            .onChange(of: detailSuppressed) { _, _ in restartDetailPopoverTimer() }
            .onChange(of: concealment.isConcealed) { _, _ in restartDetailPopoverTimer() }
            .onChange(of: isScrolling) { _, _ in restartDetailPopoverTimer() }
            .hoverCard(
                owner: item.id, isPresented: $showDetailPopover, scrolls: detailScrolls,
                callbacks: .init(onPointerInside: { pointerInsideDetail($0) }, onEscape: { closeDetailForGood() }),
                content: { detailCard }
            )
    }

    /// Split out of `body` (SwiftUI type-checker perf: this file's modifier chain is long enough
    /// that adding one more to a single expression made it time out).
    private var decoratedCard: some View {
        standardCard
            .frame(width: cardDimensions.width, height: cardDimensions.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius))
            .overlay {
                if item.analysisPending {
                    analysisPendingOverlay
                } else if isBlurredAsSensitive {
                    nsfwBlurOverlay
                }
            }
            .modifier(GlassCardModifier(
                isSelected: isSelected,
                isFocused: isFocused,
                isHovered: isPointed,
                isLifted: isLifted,
                cornerRadius: Self.cardCornerRadius
            ))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white, accent)
                        .padding(7)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay {
                if isCoveredForPrivacy {
                    // A neutral flat ground under the material: over the card's own tint the cover showed an image's or
                    // a
                    // color's dominant color (D-02).
                    RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                        .fill(Color.opaqueSurface)
                        .overlay { RoundedRectangle(cornerRadius: Self.cardCornerRadius).adaptiveMaterialFill() }
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "eye.slash.fill")
                                    .font(.system(size: 22))
                                Text("Hidden for sharing")
                                    .font(.caption2.weight(.medium))
                                Button {
                                    reveal()
                                } label: {
                                    Text("Show")
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.pestoLink)
                                .font(.caption2)
                                .help("Show this clip. Return or a click pastes it without showing it.")
                            }
                            .pestoQuiet()
                        }
                }
            }
            .offset(y: isLifted ? -6 : 0)
            .animation(Motion.animation(.spring(response: 0.22, dampingFraction: 0.72)), value: isLifted)
            .animation(Motion.animation(.easeOut(duration: 0.12)), value: isFocused)
            .animation(Motion.animation(.spring(response: 0.18, dampingFraction: 0.75)), value: isSelected)
    }

    /// Built from gridPreview so a masked secret is never read out or exposed to automation.
    var playsAnimations: Bool {
        AnimatedImagePlayback.shouldAnimate(autoPlayAllowed: autoPlayAllowed, isActive: isPointed || isFocused)
    }

    var concealment: CardConcealment {
        CardConcealment(
            screenShareBlur: isCoveredForPrivacy,
            nsfwBlurred: isBlurredAsSensitive,
            maskedSecret: item.sensitivity != nil,
            secretShown: revealedSecret != nil,
            pendingAnalysis: item.analysisPending
        )
    }

    /// Covered for a screen share or by hand, until the person shows this card with its Show. Showing it is not
    /// permanent: the cover coming back, or the shelf closing, covers it again.
    var isCoveredForPrivacy: Bool {
        isPrivacyBlurred && !(isNSFWRevealed || revealedFromOutside)
    }

    /// Anything that keeps the card's text from being drawn: a content-filter blur, a secret's mask, or the cover for a
    /// screen share.
    var hidesItsContent: Bool {
        isBlurredAsSensitive || isCoveredForPrivacy || item.sensitivity != nil
    }

    var isBlurredAsSensitive: Bool {
        item.isNSFW && nsfwMode.blursCards && !(isNSFWRevealed || revealedFromOutside)
    }

    func reveal() {
        isNSFWRevealed = true
        actions.revealChanged?(item, true)
    }

    /// ⌘Return: Show a covered clip, or Hide it again. A clip that is not hidden does nothing.
    func showShortcut() {
        if isPrivacyBlurred {
            if isCoveredForPrivacy { reveal() } else { hideAgain() }
        } else if isBlurredAsSensitive {
            reveal()
        } else if item.isNSFW, nsfwMode.blursCards {
            hideAgain()
        } else if item.sensitivity != nil, canRevealHidden {
            toggleReveal()
        }
    }

    /// An edit to this clip from one of its own popovers or menus: through the shelf's editor when there is one, so the
    /// save can roll back, the person hears of a failure and the search row follows; on its own otherwise.
    /// Built apart from `decoratedCard`: its closures and ternary were more than the compiler would type-check there.
    private var moreActions: CardMoreActions {
        let link: LinkOpenPolicy.Action = item.type == .url ? LinkOpenPolicy
            .action(for: item.displayPreviewText) : .none
        let pin: (() -> Void)? = actions.togglePin.map { toggle in { toggle(item) } }
        return CardMoreActions(
            isPinned: item.isPinned,
            togglePin: pin,
            openLink: link,
            tags: item.tags,
            removeTag: removeTagFromItem,
            isFocused: isFocused,
            spokenCard: "\(accessibility.label), \(accessibility.value)"
        )
    }

    private func removeTagFromItem(_ tag: String) {
        edit { $0.tags.removeAll { $0 == tag } }
    }

    func edit(_ change: (ClipboardItem) -> Void) {
        if let clipEditor {
            clipEditor.edit(item, change)
        } else {
            change(item)
            do {
                try modelContext.saveOrRollback()
            } catch {
                cardLoadingLogger.error("An edit was not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func hideAgain() {
        isNSFWRevealed = false
        actions.revealChanged?(item, false)
    }

    private var accessibility: CardAccessibility {
        let preview: String = if item.type == .file {
            FileClip.spokenDescription(of: item.displayPreviewText, missingCount: missingFileCount)
        } else {
            item.gridPreview
        }
        let expiry = item.expiresAt
        return CardAccessibility(
            type: item.type,
            sourceName: item.isRemote ? nil : item.sourceAppName,
            preview: preview,
            isHiddenSensitive: isBlurredAsSensitive || isCoveredForPrivacy,
            isPinned: item.isPinned,
            hotkeySlot: item.pinnedHotkeyIndex,
            burnsAfterPaste: expiry == .distantPast,
            expiresAt: expiry == .distantPast ? nil : expiry,
            tags: item.tags,
            collectionName: item.collectionID.flatMap { id in availableCollections.first { $0.id == id }?.name },
            isRemote: item.isRemote,
            age: Date.now.timeIntervalSince(item.timestamp),
            isSelected: isSelected,
            title: item.customTitle,
            secretCategory: item.sensitivity
        )
    }

    // MARK: - Card layouts

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            if hasFullWidthBody {
                cardContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            } else {
                // Text starts at the top, as in a note; centring it left short clips floating in the middle.
                cardContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.top, CardLayout.bodyTopPadding)
                Spacer(minLength: 4)
            }

            cardFooter
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
    }

    /// Pictures, colours and link pictures fill the space between header and footer; text keeps its own margins.
    private var hasFullWidthBody: Bool {
        item.type == .image || item.type == .color || (item.type == .url && urlOGImage != nil)
            || (item.isSVGSource && shownThumbnail != nil)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch item.type {
        case .image: imageBody
        case .code where item.isSVGSource && shownThumbnail != nil: imageBody
        case .color: colorBody
        case .url where urlOGImage != nil: urlImageBody
        default: cardBody
        }
    }

    /// What the card shows for its picture: the one it loaded, or the cached one at once so a card built again does not
    /// flash the placeholder first.
    var shownThumbnail: (image: NSImage, isAnimated: Bool)? {
        if let thumbnail, thumbnailByteSize == item.byteSize { return (thumbnail, thumbnailIsAnimated) }
        return ThumbnailCache.shared.entry(for: item.id, byteSize: item.byteSize).map { ($0.image, $0.isAnimated) }
    }
}

// MARK: - Drag only while the card is not covered

private extension View {
    /// A covered card cannot be dragged out: the drag would hand the clip to another app without it being shown.
    /// The modifier is always there and the provider is empty while the card is covered. An `if` that left it out
    /// swapped the view's structure when a secret was shown, which rebuilt the whole card and hid the secret again
    /// at once.
    func gatedDrag(allowed: Bool, data: @escaping () -> NSItemProvider) -> some View {
        onDrag { allowed ? data() : NSItemProvider() }
    }
}

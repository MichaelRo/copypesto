// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// The hover card: the clip itself, more than the card has room for. The whole text (rendered when it is Markdown,
/// highlighted when it is code), a link's title and address, a picture larger, a file's paths, a colour as a swatch,
/// then one line of facts. It has one button, Copy Text on a picture that read some text (ADR 0034); every other action
/// lives in the card's context menu, where it works on the whole clip. A card that scrolls or has the button takes the
/// pointer; the rest let it through (`HoverCardHost`). A secret shows only facts.
struct CardDetailPopover: View {
    let item: ClipboardItem
    var collectionName: String?
    var isRevealed: Bool
    var revealedText: String?
    var onScrollsChange: ((Bool) -> Void)?
    /// Copies the whole text of a picture; nil when the picture does not offer it.
    var onCopyRecognizedText: (() -> Bool)?
    @State private var shown: (text: String, wasCut: Bool)
    @State private var highlighted: AttributedString?
    @State private var textSize: CGSize?
    @State private var scrollEnds = ScrollEnds()
    @State private var pictureImage: NSImage?
    @State private var pictureIsAnimated: Bool = false
    @State private var linkImage: NSImage?
    @State private var linkImageIsAnimated: Bool = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    /// Text and code scroll past this, so a long clip cannot make the card cover the screen.
    private static let previewMaxHeight: CGFloat = 180
    static let width: CGFloat = 320
    private static let contentWidth: CGFloat = width - 32
    private static let cornerRadius: CGFloat = 16

    init(
        item: ClipboardItem,
        collectionName: String? = nil,
        isRevealed: Bool = false,
        revealedText: String? = nil,
        pictureImage: NSImage? = nil,
        pictureIsAnimated: Bool = false,
        linkImage: NSImage? = nil,
        linkImageIsAnimated: Bool = false,
        onScrollsChange: ((Bool) -> Void)? = nil,
        onCopyRecognizedText: (() -> Bool)? = nil
    ) {
        self.item = item
        self.collectionName = collectionName
        self.isRevealed = isRevealed
        self.revealedText = revealedText
        self.onScrollsChange = onScrollsChange
        self.onCopyRecognizedText = onCopyRecognizedText
        let effectiveSensitive = item.sensitivity != nil && !isRevealed
        let baseText = isRevealed ? (revealedText ?? item.gridPreview) : item.gridPreview
        let first = Self.cut(item, of: baseText, isSensitive: effectiveSensitive)
        _shown = State(initialValue: first)
        _highlighted = State(initialValue: Self.highlight(item, first.text, isSensitive: effectiveSensitive))
        _pictureImage = State(initialValue: pictureImage)
        _pictureIsAnimated = State(initialValue: pictureIsAnimated)
        _linkImage = State(initialValue: linkImage)
        _linkImageIsAnimated = State(initialValue: linkImageIsAnimated)
    }

    private static func cut(_ item: ClipboardItem, of text: String, isSensitive: Bool) -> (text: String, wasCut: Bool) {
        !isSensitive ? DetailPopoverContent.shown(text) : (item.gridPreview, false)
    }

    private static func highlight(_ item: ClipboardItem, _ text: String, isSensitive: Bool) -> AttributedString? {
        item.type == .code && !isSensitive
            ? CodeHighlighter.highlight(text, language: item.detectedLanguage).attributedString : nil
    }

    private var shownText: (text: String, wasCut: Bool) {
        shown
    }

    private var isSensitive: Bool {
        item.sensitivity != nil && !isRevealed
    }

    private var bodyKind: DetailPopoverContent.Body {
        DetailPopoverContent.body(type: item.type, isSensitive: isSensitive, text: shownText.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            noteRow
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Self.width, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            shape.fill(Color.opaqueSurface.opacity(0.92)).adaptiveMaterialBackground(in: shape)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(contrast == .increased ? 0.4 : 0.14), lineWidth: 1)
        }
        .accessibilityIdentifier(AccessibilityID.cardDetailPopover)
        .task(id: item.id) {
            loadFullText()
            await loadMedia()
        }
    }

    private func loadMedia() async {
        guard !isSensitive, item.sensitivityRaw == nil else { return }
        if item.type == .image || item.isSVGSource {
            if pictureImage == nil {
                if let cached = ThumbnailCache.shared.entry(for: item.id, byteSize: item.byteSize) {
                    pictureImage = cached.image
                    pictureIsAnimated = cached.isAnimated
                } else if DetailPopoverContent.canRead(byteSize: item.byteSize),
                          let blob = item.blob, let data = blob.decryptedData()
                {
                    let isAnimated = blob.mimeType == "com.compuserve.gif"
                        || blob.mimeType == "public.gif" || data.isGIF
                    if let image = await PreparedImage.image(from: data, animated: isAnimated) {
                        pictureImage = image
                        pictureIsAnimated = isAnimated
                    }
                }
            }
        } else if item.type == .url, LinkPreviewPolicy.isEnabled() {
            if linkImage == nil {
                let data: Data?
                if let direct = item.ogImageThumbnail {
                    data = direct
                } else {
                    let itemID = item.id
                    data = await Task.detached(priority: .utility) { LinkPreviewImageStore().load(for: itemID) }.value
                }
                if let data {
                    linkImage = await PreparedImage.image(from: data, animated: data.isGIF)
                    linkImageIsAnimated = data.isGIF
                }
            }
        }
    }

    /// Read when the card opens, and only for a clip small enough to decrypt on the main thread.
    private func loadFullText() {
        guard !isSensitive, item.type != .image, item.type != .color else { return }
        if let revealedText {
            let cut = Self.cut(item, of: revealedText, isSensitive: false)
            shown = cut
            highlighted = Self.highlight(item, cut.text, isSensitive: false)
            return
        }
        guard DetailPopoverContent.canRead(byteSize: item.byteSize) else { return }
        let cut = Self.cut(item, of: ClipText.full(of: item), isSensitive: false)
        shown = cut
        highlighted = Self.highlight(item, cut.text, isSensitive: false)
    }

    @ViewBuilder
    private var content: some View {
        switch bodyKind {
        case .text:
            scrolling { Text(shownText.text).scaledFont(size: 12) }
        case .markdown:
            if let attributed = renderedMarkdown {
                scrolling { Text(attributed).scaledFont(size: 12).lineSpacing(3) }
            } else {
                scrolling { Text(shownText.text).scaledFont(size: 12) }
            }
        case .code:
            scrolling(wraps: false) {
                Text(highlighted ?? AttributedString(shownText.text))
            }
        case .link:
            linkBody
        case .picture:
            pictureBody
        case .files:
            filesBody
        case .color:
            colorBody
        case .metadataOnly:
            Label("Hidden on the shelf. Show reveals it.", systemImage: "lock")
                .scaledFont(size: 12)
        }
    }

    /// The card is as tall as the text up to the cap, then the text scrolls inside it, fading at each edge it continues
    /// past. Code does not wrap, so it can scroll sideways too. A scroll view on its own takes the whole cap, so the
    /// text reports its size and the scroll view is given the smaller of that and the cap.
    private func scrolling(wraps: Bool = true, @ViewBuilder _ text: @escaping () -> some View) -> some View {
        func natural() -> some View {
            text().fixedSize(horizontal: !wraps, vertical: true)
        }
        let size = textSize ?? CGSize(width: 0, height: Self.previewMaxHeight)
        let scrollsDown = size.height > Self.previewMaxHeight + 0.5
        let scrollsAcross = !wraps && size.width > Self.contentWidth + 0.5
        return ScrollView(wraps ? [.vertical] : [.horizontal, .vertical]) {
            natural()
                .frame(minWidth: Self.contentWidth, alignment: .leading)
                .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { measured in
                    textSize = measured
                    onScrollsChange?(
                        measured.height > Self.previewMaxHeight + 0.5
                            || (!wraps && measured.width > Self.contentWidth + 0.5)
                    )
                })
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: ScrollEnds.self, of: { ScrollEnds($0) }, action: { _, ends in scrollEnds = ends })
        .frame(height: min(size.height, Self.previewMaxHeight))
        .mask(alignment: .bottom) { fade(.vertical, active: scrollsDown && !scrollEnds.atBottom) }
        .mask(alignment: .trailing) { fade(.horizontal, active: scrollsAcross && !scrollEnds.atTrailing) }
    }

    @ViewBuilder
    private func fade(_ axis: Axis, active: Bool) -> some View {
        if active {
            LinearGradient(
                stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                startPoint: axis == .vertical ? .top : .leading, endPoint: axis == .vertical ? .bottom : .trailing
            )
        } else {
            Color.black
        }
    }

    private var linkBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let img = linkImage {
                if linkImageIsAnimated {
                    let aspect = (img.size.width > 0 && img.size.height > 0) ? img.size.width / img.size.height : nil
                    AnimatedImageView(
                        image: img,
                        animates: !Motion.reduceMotion,
                        contentMode: .scaleProportionallyUpOrDown
                    )
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.previewMaxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: Self.previewMaxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            if let title = item.ogTitle ?? item.customTitle {
                Text(title).scaledFont(size: 13, weight: .semibold).fixedSize(horizontal: false, vertical: true)
            }
            if let site = item.ogSiteName {
                Text(site).scaledFont(size: 12).foregroundStyle(factsStyle)
            }
            Text(shownText.text)
                .scaledFont(size: 11, design: .monospaced)
                .foregroundStyle(factsStyle)
                .lineLimit(5)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pictureBody: some View {
        let entry = ThumbnailCache.shared.entry(for: item.id, byteSize: item.byteSize)
        let image = entry?.image ?? pictureImage
        let isAnimated = entry?.isAnimated ?? pictureIsAnimated
        return VStack(alignment: .leading, spacing: 8) {
            if let image {
                if isAnimated {
                    let aspect = (image.size.width > 0 && image.size.height > 0)
                        ? image.size.width / image.size.height : nil
                    AnimatedImageView(
                        image: image,
                        animates: !Motion.reduceMotion,
                        contentMode: .scaleProportionallyUpOrDown
                    )
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.previewMaxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: Self.previewMaxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            let inPicture = item.displayPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !inPicture.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Text in the picture").scaledFont(size: 11, weight: .semibold).foregroundStyle(factsStyle)
                        Spacer(minLength: 0)
                        if let copy = onCopyRecognizedText {
                            HoverCardCopyButton(quiet: factsStyle, copy: copy)
                        }
                    }
                    Text(String(inPicture.prefix(300))).scaledFont(size: 12).lineLimit(3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var filesBody: some View {
        let urls = FileClip.urls(from: item.displayPreviewText)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(urls.prefix(6).enumerated()), id: \.offset) { _, url in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: url.pathExtension) ?? .data))
                        .resizable()
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.lastPathComponent).scaledFont(size: 12, weight: .medium).lineLimit(1)
                        Text(url.deletingLastPathComponent().path)
                            .scaledFont(size: 11)
                            .foregroundStyle(factsStyle)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
            if urls.count > 6 {
                Text("and \(urls.count - 6) more").scaledFont(size: 11).foregroundStyle(factsStyle)
            }
        }
    }

    private var colorBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ColorStringDetector.detect(in: item.gridPreview) ?? .purple.opacity(0.5))
                .frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.14)))
            Text(item.gridPreview).scaledFont(size: 13, weight: .semibold, design: .monospaced)
        }
    }

    private var renderedMarkdown: AttributedString? {
        try? AttributedString(
            markdown: shownText.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
    }

    // MARK: - Note and footer

    @ViewBuilder
    private var noteRow: some View {
        if !isSensitive, let note = item.userNote, !note.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Note").scaledFont(size: 11, weight: .semibold).foregroundStyle(factsStyle)
                Text(note).scaledFont(size: 12).lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 8)
        }
    }

    /// Muted but readable on the card over any wallpaper: 4.5:1 or better, which `.secondary` is not on cream.
    private var factsStyle: Color {
        Color.primary.opacity(contrast == .increased ? 1 : 0.72)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(DetailFactsText.line(
                DetailFactsText.facts(
                    for: item,
                    collectionName: collectionName,
                    shownText: shownText.text,
                    wasCut: shownText.wasCut,
                    isRevealed: isRevealed
                ),
                calendar: calendar,
                locale: locale
            ))
            .scaledFont(size: 11)
            .foregroundStyle(factsStyle)
            .fixedSize(horizontal: false, vertical: true)
            if let slot = item.pinnedHotkeyIndex {
                HStack(spacing: 6) {
                    Keycap(symbol: "⌃\(slot)", size: .compact)
                    Text("pastes this clip from anywhere").scaledFont(size: 11).foregroundStyle(factsStyle)
                }
            }
        }
        .padding(.top, 10)
    }
}

/// Whether a scroll view has reached the end of its content, so the fade that says "more" can go.
struct ScrollEnds: Equatable {
    var atBottom = true
    var atTrailing = true

    init() {}

    init(_ geometry: ScrollGeometry) {
        atBottom = geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 1
        atTrailing = geometry.contentOffset.x + geometry.containerSize.width >= geometry.contentSize.width - 1
    }
}

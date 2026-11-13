// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension ClipboardCard {
    @ViewBuilder
    var stateBadges: some View {
        if let expiry = item.expiresAt {
            let isBurnAfterPaste = expiry == .distantPast
            Image(systemName: isBurnAfterPaste ? "flame.fill" : "clock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isBurnAfterPaste ? Color.orange : Color.secondary)
        }
        if item.isPinned, item.isTemplate {
            Image(systemName: "curlybraces")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent.opacity(0.9))
        }
    }

    @ViewBuilder
    var cardBody: some View {
        if isRenamingTitle {
            renameOverlay
        } else if item.sensitivity != nil {
            sensitiveBody
        } else if isGlyphCard {
            glyphBody
        } else if item.type == .url, item.ogTitle != nil || item.ogSiteName != nil || urlFavicon != nil {
            urlRichBody
        } else if item.type == .file {
            FileCardBody(text: item.displayPreviewText, animates: playsAnimations)
        } else if CardPreviewText.display(item.gridPreview).isEmpty {
            emptyBodyPlaceholder
        } else {
            paragraphBody
        }
    }

    var paragraphBody: some View {
        CardParagraphText(
            paragraphs: CardPreviewText.paragraphs(item.gridPreview),
            fontSize: bodySize(item.type == .code ? 12 : 13),
            design: item.type == .code ? .monospaced : .default,
            budget: CardLayout.textBlockHeight(for: cardDimensions)
        )
    }

    var emptyBodyPlaceholder: some View {
        Color.white.opacity(0.06)
            .overlay {
                Image(systemName: typeMeta.symbol)
                    .font(.title2)
                    .foregroundStyle(AdaptiveContrast.quiet(contrast))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// How many lines of text fit between the header and the footer at the chosen card size.
    var textLineLimit: Int {
        CardLayout.textLineLimit(for: cardDimensions)
    }

    /// Body text follows the card-size setting (`CardTextScale`): larger cards draw larger text.
    func bodySize(_ base: CGFloat) -> CGFloat {
        CardTextScale.size(base, cardWidth: cardDimensions.width)
    }

    var renameOverlay: some View {
        TextField("Title", text: $renameText)
            .focused($renameFieldFocused)
            // The context menu that started the rename is still closing, and hands the keyboard back to the shelf
            // when it has gone, so the field asks for it a moment later.
            .task {
                try? await Task.sleep(for: .milliseconds(200))
                renameFieldFocused = true
            }
            // Text size capped: fills a fixed-size card.
            .scaledFont(size: bodySize(13), maxScale: 1.3)
            .textFieldStyle(.plain)
            .onSubmit {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                edit { $0.customTitle = trimmed.isEmpty ? nil : trimmed }
                isRenamingTitle = false
            }
            .onExitCommand {
                isRenamingTitle = false
            }
    }

    var urlRichBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 5) {
                if let favicon = urlFavicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.blue.opacity(0.8))
                }
                Text(item.ogSiteName ?? URL(string: item.displayPreviewText)?.host ?? "")
                    .scaledFont(size: 10, weight: .medium, maxScale: 1.3)
                    .pestoQuiet()
                    .lineLimit(1)
            }
            if let title = item.ogTitle {
                Text(title)
                    .scaledFont(size: bodySize(13), weight: .semibold, maxScale: 1.3)
                    .lineLimit(3)
                    .foregroundStyle(.primary.opacity(0.9))
            }
        }
    }

    var sensitiveBody: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: revealedSecret == nil ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.statusWarning)
                .padding(.top, 1)
            if let revealedSecret {
                Text(revealedSecret)
                    .scaledFont(size: bodySize(13), maxScale: 1.3)
                    .lineLimit(textLineLimit)
                    .foregroundStyle(.primary)
            } else {
                Text(item.localizedMaskedPreview ?? item.sensitivityMaskedPreview ?? "Secret")
                    .scaledFont(size: bodySize(13), maxScale: 1.3)
                    .lineLimit(3)
                    .pestoQuiet()
            }
            Spacer(minLength: 0)
            if canRevealHidden {
                Button {
                    toggleReveal()
                } label: {
                    Image(systemName: revealedSecret == nil ? "eye" : "eye.slash")
                        .font(.system(size: 11))
                        .pestoQuiet()
                        .pestoHitTarget()
                }
                .buttonStyle(.plain)
                .help(revealedSecret == nil ? "Show" : "Hide")
                .accessibilityLabel(revealedSecret == nil ? "Show" : "Hide")
                .accessibilityIdentifier(AccessibilityID.revealHiddenClip)
            }
        }
    }

    /// Shows a masked clip's real text until Hide, after Touch ID or the account password; it also hides when the card
    /// leaves the screen, the shelf closes, the history locks or the contents are covered (ADR 0003). Quick Look asks
    /// the same, so neither is a way round the other.
    func toggleReveal() {
        guard revealedSecret == nil else {
            hideSecret()
            return
        }
        Task {
            let reason = "Show a clip that is hidden on the shelf"
            let permitted = if let authenticate = actions.authenticate {
                await authenticate(reason)
            } else {
                await HiddenClipReveal.permitted(isHidden: true, using: UserAuthenticator.current, reason: reason)
            }
            guard permitted,
                  let text = HiddenClipReveal.readableText(from: item.blob?.decryptedData()) else { return }
            revealedSecret = text
        }
    }

    func hideSecret() {
        revealedSecret = nil
        decodedJWT = nil
    }

    func releaseOffscreenThumbnail() {
        urlOGImage = nil
        urlFavicon = nil
    }

    /// Copy Payload, from the button or Return: the payload goes out concealed and the popover closes.
    func copyDecodedPayload(_ text: String? = nil) {
        guard case let .decoded(decoding)? = decodedJWT else { return }
        actions.copyProtectedText?(text ?? decoding.payloadJSON)
        decodedJWT = nil
    }

    /// Decode JWT: the same authentication as Show, and the popover goes where Show goes (ADR 0020).
    func decodeJWT() {
        guard let decode = actions.decodeJWT else { return }
        Task {
            guard let result = await decode(item) else { return }
            decodedJWT = result
        }
    }

    func footerDetail(withLines: Bool) -> String? {
        switch item.type {
        case .text, .code: characterCountText(withLines: withLines)
        case .color: item.gridPreview
        case .image: ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file)
        default: nil
        }
    }

    func shortcutKeycap(_ number: Int) -> some View {
        Keycap(symbol: "\u{2318}\(number)", size: .compact)
            .accessibilityHidden(true)
    }

    /// `onDark` is a row over a picture or color, where a chip's usual tint would not read: white text on a dark chip.
    func tagChipsRow(onDark: Bool = false) -> some View {
        let over = pictureOverlay
        // A clipped row, not a nested ScrollView: a horizontal scroll view inside the shelf's own one took trackpad
        // scrolls that began over a tag, so the shelf stuck.
        return HStack(spacing: 3) {
            ForEach(item.tags, id: \.self) { tag in
                Button {
                    tagToRemove = tag
                    showRemoveTagConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(tagColor(for: tag)).frame(width: 6, height: 6)
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(onDark ? over.ink : Color.primary)
                    }
                    .padding(.horizontal, 6)
                    .frame(minHeight: 20)
                    .background(
                        onDark ? surface.opacity(PictureScrim.pillOpacity) : tagColor(for: tag).opacity(0.18),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tag \(tag)")
                .accessibilityHint("Removes this tag after confirming")
                .confirmationDialog(
                    "Remove tag \"\(tag)\"?",
                    isPresented: Binding(
                        get: { showRemoveTagConfirmation && tagToRemove == tag },
                        set: { if !$0 { showRemoveTagConfirmation = false } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        edit { clip in
                            var updated = clip.tags
                            updated.removeAll { $0 == tag }
                            clip.tags = updated
                        }
                        showRemoveTagConfirmation = false
                        tagToRemove = nil
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    func tagColor(for tag: String) -> Color {
        // FNV-1a 32-bit: stable across processes (unlike Swift's per-process hashValue).
        // This ensures the same tag always gets the same hue across app launches.
        var h: UInt32 = 2_166_136_261
        for byte in tag.utf8 {
            h = (h ^ UInt32(byte)) &* 16_777_619
        }
        return Color(hue: Double(h & 0xFFFF) / 65_536.0, saturation: 0.7, brightness: 0.85)
    }

    var detectedColor: Color? {
        guard item.type == .color else { return nil }
        return ColorStringDetector.detect(in: item.gridPreview)
    }

    func sensitivityBadge(_ category: SensitivityCategory) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(Color.statusWarning)
            Text(category.badgeLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.85))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(Color.orange.opacity(0.22), in: Capsule())
    }

    func characterCountText(withLines: Bool) -> String? {
        guard item.type == .text || item.type == .code, item.sensitivity == nil else { return nil }
        let previewLimit = CardPreviewText.previewLength
        let known = item.textLength
        let preview = item.displayPreviewText
        let count = known > 0 ? known : preview.count
        guard count > 0 else { return nil }
        if known == 0, count >= previewLimit { return "\(previewLimit)+ characters" }
        let characters = String(localized: "\(count) characters")
        guard withLines, let lines = CardPreviewText.footerLineCount(of: preview, textLength: known) else {
            return characters
        }
        return characters + " \u{00B7} " + String(localized: "\(lines) lines")
    }

    var timeAgo: String {
        CardAge.text(for: item, inCollection: showsFirstCopyTime)
    }

    struct BadgeMeta {
        let label: String
        let symbol: String
        let color: Color
    }

    var typeMeta: BadgeMeta {
        let presentation = item.type.presentation
        let label = item.type == .code ? (item.detectedLanguage.map(\.capitalized) ?? presentation.label) : presentation
            .label
        return BadgeMeta(label: label, symbol: presentation.symbolName, color: typeColor)
    }

    var typeColor: Color {
        switch item.type {
        case .text: .secondary
        case .url: .blue
        case .image: .orange
        case .file: Color(red: 0.65, green: 0.42, blue: 0.18)
        case .color: .purple
        case .code: .green
        }
    }

    func collectionBadge(_ collection: CollectionRef, showsName: Bool = true) -> some View {
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
        .foregroundStyle(AdaptiveContrast.quiet(contrast))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        // A material, not glass: cards are content and Liquid Glass is chrome, and a `.glassEffect` on every card in a
        // collection cost about 8 ms of a 60 ms collection switch over a long history (docs/perf/shelf-2026-11.md). Not
        // GlassChipModifier: that fallback renders `.clear` at rest, and this badge sits directly on arbitrary card
        // content and imagery, so it stays visibly frosted.
        .adaptiveMaterialBackground(in: Capsule())
        .padding(5)
    }
}

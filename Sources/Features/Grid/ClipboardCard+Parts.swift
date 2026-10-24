// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension ClipboardCard {
    static let neutralAppColorHex = "#888888"
    /// The theme's own wash across every header, and how much of the source app's colour stays on top of it: the
    /// app colour still says where a clip came from, but the shelf reads in the theme's colour, not a rainbow.
    static let themeWashOpacity = 0.08
    static let appWashShare = 0.32

    /// The source app's colour as a soft tint under the header. A neutral icon (no real colour could be sampled)
    /// gets a quiet grey instead of a colour it does not have.
    var headerTint: Color {
        if item.isRemote { return accent.opacity(colorScheme == .dark ? 0.22 : 0.20) }
        guard let hex = item.sourceDominantColorHex, hex != Self.neutralAppColorHex, let color = Color(hex: hex) else {
            return Color.gray.opacity(0.16)
        }
        return color.opacity(colorScheme == .dark ? 0.26 : 0.36)
    }

    @ViewBuilder
    var headerBadges: some View {
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

    /// "Text" tells nothing the card does not already show, so a plain text clip names the app it came from; the other
    /// kinds (Link, Image, Color, Code, File) keep their label, because it is what sets them apart.
    var headerNamesTheApp: Bool {
        item.customTitle == nil && item.type == .text && item.sourceAppName != nil && !item.isRemote
    }

    var headerTitle: String {
        if let title = item.customTitle { return title }
        if shownThumbnail?.isAnimated == true { return "GIF" }
        if headerNamesTheApp, let app = item.sourceAppName { return app }
        return typeMeta.label
    }

    var cardHeader: some View {
        HStack(alignment: .center, spacing: 9) {
            if let customSymbol = item.customSymbolName {
                CollectionIcon(symbolName: customSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: CardLayout.appTileSize, height: CardLayout.appTileSize)
                    .background(headerTint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else if item.isRemote {
                RemoteSourceTile()
            } else {
                SourceAppIconView(
                    bundleID: item.sourceBundleID,
                    appName: item.sourceAppName,
                    size: CardLayout.appTileSize
                )
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(headerTitle)
                Text(isPointed && !headerNamesTheApp ? (item.sourceAppName ?? timeAgo) : timeAgo)
                    .font(.caption2)
                    .foregroundStyle(AdaptiveContrast.quiet(contrast))
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            headerBadges
            if let slot = item.pinnedHotkeyIndex {
                Keycap(symbol: "⌃\(slot)", size: .compact).accessibilityHidden(true)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, options: .nonRepeating, value: Motion.reduceMotion ? false : item.isPinned)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: CardLayout.headerHeight)
        .background {
            ZStack {
                accent.opacity(Self.themeWashOpacity)
                LinearGradient(
                    colors: [headerTint.opacity(Self.appWashShare), .clear], startPoint: .top, endPoint: .bottom
                )
            }
        }
        .animation(Motion.animation(.easeOut(duration: 0.14)), value: isPointed)
    }

    @ViewBuilder
    var cardBody: some View {
        if isRenamingTitle {
            renameOverlay
        } else if item.sensitivity != nil {
            sensitiveBody
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
    }

    var cardFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !item.tags.isEmpty {
                tagChipsRow
            }
            ViewThatFits(in: .horizontal) {
                footerLine(detail: footerDetail(withLines: true))
                footerLine(detail: footerDetail(withLines: false))
                footerLine(detail: nil)
            }
        }
    }

    func footerLine(detail: String?) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if let number = shortcutNumber {
                shortcutKeycap(number)
            }
            if let detail {
                Text(detail)
                    .font(item.type == .color ? .system(.caption2, design: .monospaced) : .caption2)
                    .foregroundStyle(AdaptiveContrast.quiet(contrast))
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if item.pasteCount >= 2 {
                Text("\u{2191}\(item.pasteCount)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AdaptiveContrast.quiet(contrast))
            }
            if let collectionID = item.collectionID,
               let collection = availableCollections.first(where: { $0.id == collectionID })
            {
                collectionBadge(collection)
                    .lineLimit(1)
            }
            if let cat = item.sensitivity {
                sensitivityBadge(cat)
            }
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

    var tagChipsRow: some View {
        // A clipped row, not a nested ScrollView: a horizontal scroll view inside the shelf's own one took trackpad
        // scrolls that began over a tag, so the shelf stuck.
        HStack(spacing: 3) {
            ForEach(item.tags, id: \.self) { tag in
                Button {
                    tagToRemove = tag
                    showRemoveTagConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(tagColor(for: tag)).frame(width: 6, height: 6)
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 6)
                    .frame(minHeight: 20)
                    .background(tagColor(for: tag).opacity(0.18), in: Capsule())
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
        let interval = Date.now.timeIntervalSince(item.timestamp)
        switch interval {
        case ..<60: return "just now"
        case 60..<3600: return "\(Int(interval / 60))m ago"
        case 3600..<86_400: return "\(Int(interval / 3600))h ago"
        default: return "\(Int(interval / 86_400))d ago"
        }
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

    func collectionBadge(_ collection: CollectionRef) -> some View {
        HStack(spacing: 3) {
            CollectionIcon(symbolName: collection.symbolName)
                .font(.caption2.weight(.medium))
            Text(collection.name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(AdaptiveContrast.quiet(contrast))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        // Not GlassChipModifier: that fallback renders `.clear` at rest (fine for CollectionChip's
        // command-bar context), but this badge sits directly on arbitrary card content/imagery and
        // needs to stay visibly frosted on macOS 15 for legibility.
        .glassPanelBackground(in: Capsule())
        .padding(5)
    }
}

// MARK: - SensitivityCategory display

extension SensitivityCategory {
    var badgeLabel: String {
        switch self {
        case .creditCard: "Card"
        case .ssn: "SSN"
        case .jwt: "JWT"
        case .apiKey: "API Key"
        case .oauthToken: "OAuth"
        case .privateKey: "Private Key"
        case .password: "Password"
        case .credential: "Credential"
        }
    }
}

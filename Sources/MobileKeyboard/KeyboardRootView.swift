// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The keyboard as a small Pesto shelf (ADRs 0061, 0062): chips on top like the Mac shelf's (the word typed before
/// switching, then Recent, Pinned, Snippets and the chosen collections), the clips as cards in a row that scrolls
/// sideways (one or two rows on iPhone, one on iPad), or the numbers pad, above Globe, 123, Search, Space, Return
/// and Delete. The search key opens `KeyboardSearchPage` (ADR 0063).
struct KeyboardRootView: View {
    let model: KeyboardModel
    let keys: KeyboardKeys
    weak var controller: UIInputViewController?

    @State private var showsPad = false
    @State private var showsSettings = false
    @State private var chip: KeyboardMenu.Chip?
    @State private var feedback: (id: UUID, kind: KeyboardClipKey.Feedback)?
    @State private var isScreenCaptured = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedAccent: Color {
        Color(hex: model.menu.accent.accent(dark: colorScheme == .dark)) ?? BrandAccent.color
    }

    private var resolvedAccentLabel: Color {
        let hex = model.menu.accent.accent(dark: colorScheme == .dark)
        return Color(hex: ContrastRatio.labelHex(onFill: hex)) ?? .white
    }

    private var resolvedSurface: Color {
        Color(hex: model.menu.accent.ground(dark: colorScheme == .dark)) ?? .opaqueSurface
    }

    var body: some View {
        // Searched once per pass: every chip and card below reads the same matches.
        let matches = word.map(model.menu.entries(matching:)) ?? []
        ZStack {
            Group {
                if model.isSearching {
                    KeyboardSearchPage(
                        model: model, globe: model.showsGlobeKey ? GlobeKey(controller: controller) : nil,
                        pick: { entry, longPress in
                            setSearching(false)
                            if entry.kind == .image {
                                copyPicture(entry)
                            } else {
                                // No matches on purpose: a clip found by the page's own query never deletes the app's
                                // text.
                                insert(entry, longPress: longPress, matches: [])
                            }
                        },
                        pickRecognizedText: { entry, text in
                            setSearching(false)
                            insertRecognizedText(text, for: entry)
                        },
                        close: { setSearching(false) }
                    )
                } else if showsSettings {
                    KeyboardSettingsPanel(
                        size: model.keyboardSize,
                        sample: shown(matches),
                        chipTitles: model.menu.chips.map(\.title),
                        theme: model.menu.accent,
                        appIcons: model.menu.appIcons,
                        setSize: setKeyboardSize,
                        openSettings: keys.openURL.map { open in { open(AppLink.url(for: .keyboardSettings)) } },
                        close: { showsSettings = false }
                    )
                } else {
                    VStack(spacing: 6) {
                        if model.menu.state == .ready, !showsPad { chipRow(matches: matches) }
                        content(matches: matches)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        bottomRow(matches: matches)
                    }
                }
            }
            .blur(radius: isScreenCaptured ? 16 : 0)
            .allowsHitTesting(!isScreenCaptured)
            .accessibilityHidden(isScreenCaptured)

            if isScreenCaptured, model.menu.state == .ready {
                VStack(spacing: 4) {
                    Image(systemName: "eye.slash.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    note("Clips are hidden while the screen is recorded or shared.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            SceneCaptureReader { isScreenCaptured = $0 }
        }
        .environment(\.pestoAccent, resolvedAccent)
        .environment(\.pestoAccentLabel, resolvedAccentLabel)
        .environment(\.pestoSurface, resolvedSurface)
        .tint(resolvedAccent)
        .sensoryFeedback(.impact(weight: .light), trigger: feedback?.id)
    }

    /// The word the person typed before switching, unless they took it off with its chip.
    private var word: String? {
        guard let word = model.word, word != model.dismissedWord else { return nil }
        return word
    }

    private var selectedChip: KeyboardMenu.Chip? {
        let available = model.menu.chips.map(\.chip)
        if let chip, available.contains(chip) { return chip }
        return available.first
    }

    private func shown(_ matches: [QuickInsertEntry]) -> [QuickInsertEntry] {
        if !matches.isEmpty { return matches }
        guard let selectedChip else { return [] }
        return model.menu.entries(for: selectedChip)
    }

    @ViewBuilder
    private func content(matches: [QuickInsertEntry]) -> some View {
        switch model.menu.state {
        case .restricted:
            VStack(spacing: 8) {
                note("To show your clips, allow Full Access in Settings > General > Keyboard > Keyboards > Pesto.")
                KeyboardPad(insert: keys.insert)
            }
        case _ where showsPad:
            KeyboardPad(insert: keys.insert)
        case .unavailable:
            VStack(spacing: 8) {
                note("Open Pesto once so your clips are ready here.")
                if let openURL = keys.openURL {
                    settingsPill("Open Pesto Settings") { openURL(AppLink.url(for: .keyboardSettings)) }
                }
                KeyboardPad(insert: keys.insert)
            }
        case .locked:
            VStack(spacing: 8) {
                Label("Pesto is Locked", systemImage: "lock.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if let openURL = keys.openURL {
                    Button {
                        openURL(AppLink.url(for: .unlock))
                    } label: {
                        Label("Unlock in Pesto", systemImage: "lock.open")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .empty:
            VStack(spacing: 8) {
                note("No text clips yet. Clips with secrets never appear here.")
                if let openURL = keys.openURL {
                    settingsPill("Keyboard Settings") { openURL(AppLink.url(for: .keyboardSettings)) }
                }
            }
        case .ready:
            shelf(matches: matches)
        }
    }

    private func settingsPill(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "gearshape")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
    }

    private func chipRow(matches: [QuickInsertEntry]) -> some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let word {
                        KeyboardChip(
                            title: "\u{201C}\(word)\u{201D}", symbolName: "xmark", isSelected: !matches.isEmpty,
                            isDimmed: matches.isEmpty
                        ) { model.dismissedWord = word }
                            .accessibilityLabel(Text("Matching \(word)"))
                            .accessibilityHint(Text("Shows all clips again"))
                    }
                    ForEach(model.menu.chips, id: \.chip) { label in
                        KeyboardChip(
                            title: label.title, symbolName: label.symbolName,
                            isSelected: matches.isEmpty && label.chip == selectedChip, isDimmed: false,
                            tint: label.color.isEmpty ? nil : Color(hex: label.color)
                        ) {
                            if let word { model.dismissedWord = word }
                            chip = label.chip
                        }
                    }
                    KeyboardChip(title: nil, symbolName: "gearshape", isSelected: false, isDimmed: false) {
                        showsSettings = true
                    }
                    .accessibilityLabel(Text("Keyboard Settings"))
                }
            }
            .scrollEdgeEffectHidden(true, for: .all)

            Button { setSearching(true) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(KeyboardKeyStyle())
            .clipShape(.capsule)
            .accessibilityLabel(Text("Search Clips"))
        }
        .environment(\.layoutDirection, KeyboardLetters.isActiveLocaleRTL ? .rightToLeft : .leftToRight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setKeyboardSize(_ size: KeyboardSize) {
        if let setKeyboardSize = keys.setKeyboardSize {
            setKeyboardSize(size)
        } else {
            model.keyboardSize = size
            keys.relayout()
        }
    }

    private func shelf(matches: [QuickInsertEntry]) -> some View {
        let isRegular = sizeClass == .regular
        let isLandscape = verticalSizeClass == .compact
        let rowCount = KeyboardLayout.rows(
            size: model.keyboardSize,
            isRegular: isRegular,
            isLandscape: isLandscape
        )
        let cardSize = KeyboardLayout.cardSize(size: model.keyboardSize, isRegular: isRegular)
        let rows = Array(repeating: GridItem(.fixed(cardSize.height), spacing: 6), count: rowCount)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 6) {
                ForEach(shown(matches)) { entry in
                    cardView(entry: entry, cardSize: cardSize, matches: matches)
                }
            }
        }
        .scrollEdgeEffectHidden(true, for: .all)
        .environment(\.layoutDirection, KeyboardLetters.isActiveLocaleRTL ? .rightToLeft : .leftToRight)
        .id(shownIdentity)
    }

    @ViewBuilder
    private func cardView(
        entry: QuickInsertEntry, cardSize: CGSize, matches: [QuickInsertEntry]
    )
    -> some View {
        let entryFeedback = feedback?.id == entry.id ? feedback?.kind : nil
        KeyboardClipKey(
            entry: entry, cardSize: cardSize, feedback: entryFeedback, theme: model.menu.accent,
            appIcon: model.menu.appIcon(for: entry)
        )
        .overlay {
            // Only the clip Return would insert is ringed: a picture is copied, never inserted (ADR 0066).
            if entry.id == returnInserts(matches)?.id {
                RoundedRectangle(cornerRadius: CardGridLayout.cornerRadius, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 2)
                    .accessibilityHidden(true)
            }
        }
        .modifier(KeyboardCardActions(
            entry: entry,
            returnsAfterInsert: model.menu.returnsAfterInsert,
            choose: { longPress in
                if entry.kind == .image {
                    copyPicture(entry)
                } else {
                    insert(entry, longPress: longPress, matches: matches)
                }
            },
            useRecognizedText: { text in insertRecognizedText(text, for: entry) }
        ))
    }

    /// A new chip or search starts the row at its first card.
    private var shownIdentity: String {
        word.map { "word:\($0)" } ?? "\(String(describing: selectedChip))"
    }

    /// A tap does what the person chose in Settings (return to their keyboard, or stay); a long press does the other.
    /// A clip picked from a search replaces the word it was found by.
    private func insert(_ entry: QuickInsertEntry, longPress: Bool, matches: [QuickInsertEntry]) {
        if let word, matches.contains(entry) {
            if !model.wordIsSelection {
                // The field is read again now: if the caret moved, or the word was already replaced, nothing is
                // deleted. A selected range is replaced by `insert(_:)` natively without extra deletes.
                let count = KeyboardWord.deletions(
                    replacing: word,
                    before: keys.contextBefore(),
                    after: keys.contextAfter()
                )
                for _ in 0..<(count ?? 0) {
                    keys.deleteBackward()
                }
            }
            model.dismissedWord = word
        }
        let text = entry.insertionText()
        keys.insert(text)
        finishInsert(entry: entry, longPress: longPress, inserted: text)
    }

    private func insertRecognizedText(_ text: String, for entry: QuickInsertEntry) {
        keys.insert(text)
        finishInsert(entry: entry, longPress: false, inserted: text)
    }

    private func finishInsert(entry: QuickInsertEntry, longPress: Bool, inserted: String) {
        if model.menu.returnsAfterInsert != longPress {
            keys.switchKeyboard()
            return
        }
        model.noteInsert(inserted)
        showFeedback(.inserted, for: entry.id, duration: .milliseconds(600))
    }

    private func copyPicture(_ entry: QuickInsertEntry) {
        guard model.menu.state == .ready, let data = entry.thumbnail else { return }
        AppPasteboard.general.setItems(
            [[UTType.jpeg.identifier: data]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)]
        )
        showFeedback(.copiedImage, for: entry.id, duration: .milliseconds(1500))
    }

    private func showFeedback(_ kind: KeyboardClipKey.Feedback, for id: UUID, duration: Duration) {
        feedback = (id, kind)
        let announcement = switch kind {
        case .inserted: String(localized: "Inserted ✓")
        case .copiedImage: String(localized: "Copied, paste it")
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
        Task { @MainActor in
            try? await Task.sleep(for: duration)
            if feedback?.id == id, feedback?.kind == kind { feedback = nil }
        }
    }

    private func setSearching(_ isOn: Bool) {
        if isOn { model.openSearch() } else { model.closeSearch() }
        keys.relayout()
    }

    /// The first match of the word before the caret, which Return inserts (ADR 0066); a picture is never one, since
    /// it is copied rather than inserted.
    private func returnInserts(_ matches: [QuickInsertEntry]) -> QuickInsertEntry? {
        guard word != nil, !showsPad, let first = matches.first, first.kind != .image else { return nil }
        return first
    }

    private func bottomRow(matches: [QuickInsertEntry]) -> some View {
        HStack(spacing: 6) {
            if model.menu.state != .restricted {
                Button { showsPad.toggle() } label: {
                    padToggleLabel.frame(width: 50, height: 42)
                }
                .buttonStyle(KeyboardKeyStyle(isFunction: true))
            }
            if model.showsGlobeKey {
                GlobeKey(controller: controller)
                    .frame(width: 44, height: 42)
            }
            Button { keys.insert(" ") } label: {
                Text("Space").frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(KeyboardKeyStyle())
            .buttonRepeatBehavior(.enabled)
            Button(action: keys.deleteBackward) {
                Image(systemName: "delete.left").frame(width: 50, height: 42)
            }
            .buttonStyle(KeyboardKeyStyle(isFunction: true))
            .buttonRepeatBehavior(.enabled)
            .accessibilityLabel(Text("Delete"))
            if let first = returnInserts(matches) {
                Button { insert(first, longPress: false, matches: matches) } label: {
                    Text("Insert").fontWeight(.semibold).frame(width: 88, height: 42)
                }
                .buttonStyle(KeyboardKeyStyle(isAccent: true))
                .accessibilityHint(Text("Inserts the first match"))
            } else {
                Button { keys.insert("\n") } label: {
                    Text("return").frame(width: 88, height: 42)
                }
                .buttonStyle(KeyboardKeyStyle(isFunction: true))
                .accessibilityLabel(Text("Return"))
            }
        }
        .font(.body)
        .tint(.primary)
    }

    @ViewBuilder
    private var padToggleLabel: some View {
        if showsPad {
            Image(systemName: "rectangle.on.rectangle")
                .accessibilityLabel(Text("Clips"))
        } else {
            Text(verbatim: "123")
                .accessibilityLabel(Text("Numbers"))
        }
    }
}

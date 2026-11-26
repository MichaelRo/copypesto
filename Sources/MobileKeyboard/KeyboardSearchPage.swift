// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The search page (ADR 0063): Pesto's own search field, the matching clips in one row, and letters (or numbers) that
/// type into that field only. Picking a clip is the one thing that reaches the app, through `pick`.
struct KeyboardSearchPage: View {
    let model: KeyboardModel
    /// iOS's switch key, built by the root: the page holds no input controller, so nothing on it can reach the field.
    let globe: GlobeKey?
    let pick: (QuickInsertEntry, _ longPress: Bool) -> Void
    var pickRecognizedText: (QuickInsertEntry, String) -> Void = { _, _ in }
    let close: () -> Void

    @State private var showsDigits = false
    @State private var layoutIndex = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isRegular: Bool {
        sizeClass == .regular
    }

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var layouts: [SearchKeyboardLayout] {
        KeyboardLetters.resolvedLayouts()
    }

    private var activeLayout: SearchKeyboardLayout {
        layouts[layoutIndex % layouts.count]
    }

    private var searchDirection: LayoutDirection {
        activeLayout.isRTL ? .rightToLeft : .leftToRight
    }

    private var query: KeyboardQuery {
        model.searchQuery ?? KeyboardQuery()
    }

    private var results: [QuickInsertEntry] {
        if let search = query.search { return model.menu.entries(matching: search) }
        return model.menu.chips.first.map { model.menu.entries(for: $0.chip) } ?? []
    }

    private var placeholder: Text {
        if let missing = KeyboardLetters.inputMethodLanguages().first,
           let name = Locale.current.localizedString(forLanguageCode: missing)
        {
            return Text("Search your clips (\(name) needs the system keyboard)")
        }
        return Text("Search your clips")
    }

    var body: some View {
        VStack(spacing: KeyboardSearchMetrics.sectionSpacing(isRegular: isRegular, isLandscape: isLandscape)) {
            field
                .environment(\.layoutDirection, searchDirection)
            resultTray
                .environment(\.layoutDirection, KeyboardLetters.isActiveLocaleRTL ? .rightToLeft : .leftToRight)
            KeyboardLetters(
                model: model, layout: showsDigits ? .digits : .letters(activeLayout), done: isRegular ? close : nil
            )
            .zIndex(1)
            bottomRow
        }
        .padding(.vertical, isRegular ? 9 : isLandscape ? 5 : 7)
    }

    private var field: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Group {
                    if query.text.isEmpty {
                        placeholder.foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: query.text).foregroundStyle(.primary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isSearchField)
            if !query.text.isEmpty {
                Button(action: model.clearSearch) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear Search"))
            }
        }
        .font(isRegular ? .title3 : .body)
        .padding(.horizontal, 12)
        .frame(height: KeyboardSearchMetrics.fieldHeight(isRegular: isRegular, isLandscape: isLandscape))
        .background(Color(.systemBackground), in: Capsule())
        .padding(.horizontal, 6)
    }

    private var resultTray: some View {
        resultRow
            .padding(6)
            .frame(
                height: KeyboardSearchMetrics.trayHeight(
                    size: model.keyboardSize, isRegular: isRegular, isLandscape: isLandscape
                )
            )
            .background(Color(.systemBackground).opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var resultRow: some View {
        if results.isEmpty {
            Text("No clips match.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                let cardSize = KeyboardSearchMetrics.landscapeAdjusted(
                    KeyboardSearchMetrics.resultCard(size: model.keyboardSize, isRegular: isRegular),
                    isLandscape: isLandscape
                )
                let rowCount = KeyboardSearchMetrics.resultRows(
                    size: model.keyboardSize, isRegular: isRegular, isLandscape: isLandscape
                )
                LazyHGrid(
                    rows: Array(repeating: GridItem(.fixed(cardSize.height), spacing: 6), count: rowCount),
                    spacing: 6
                ) {
                    ForEach(results) { entry in
                        KeyboardClipKey(entry: entry, cardSize: cardSize, feedback: nil)
                            .modifier(KeyboardCardActions(
                                entry: entry,
                                returnsAfterInsert: model.menu.returnsAfterInsert,
                                choose: { longPress in pick(entry, longPress) },
                                useRecognizedText: { text in pickRecognizedText(entry, text) }
                            ))
                    }
                }
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .id(query.search ?? "")
        }
    }

    private var bottomRow: some View {
        let height = KeyboardSearchMetrics.bottomKeyHeight(isRegular: isRegular, isLandscape: isLandscape)
        return HStack(spacing: KeyboardSearchMetrics.keyGap(isRegular: isRegular)) {
            Button { showsDigits.toggle() } label: {
                Text(verbatim: showsDigits ? "ABC" : "123").frame(width: isRegular ? 86 : 50, height: height)
            }
            .buttonStyle(KeyboardKeyStyle(isFunction: true))
            .accessibilityLabel(showsDigits ? Text("Letters") : Text("Numbers"))
            if let globe {
                globe.frame(width: 44, height: height)
            }
            spaceKey(height: height)
            if !isRegular {
                Button(action: close) {
                    Text("Done").fontWeight(.semibold).frame(width: 88, height: height)
                }
                .buttonStyle(KeyboardKeyStyle(isAccent: true))
            }
        }
        .font(.body)
        .padding(.horizontal, 3)
    }

    /// Space types a space; held, it moves to the next of the person's own layouts, whose name it shows.
    private func spaceKey(height: CGFloat) -> some View {
        let name = Locale(identifier: activeLayout.languageCode)
            .localizedString(forLanguageCode: activeLayout.languageCode)?.localizedCapitalized
        return Group {
            if layouts.count > 1, !showsDigits, let name { Text(verbatim: name) } else { Text("Space") }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: height)
        .background {
            RoundedRectangle(cornerRadius: isRegular ? 7 : 5, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
        }
        .contentShape(.rect)
        // A tap and a hold are told apart here; a Button would also type a space at the end of the hold.
        .onTapGesture { model.typeInSearch(" ") }
        .onLongPressGesture(minimumDuration: 0.5) { nextLayout() }
        .accessibilityElement()
        .accessibilityLabel(Text("Space"))
        .accessibilityAddTraits([.isKeyboardKey, .isButton])
        .accessibilityAction { model.typeInSearch(" ") }
        .accessibilityAction(named: Text("Next Search Keyboard")) { nextLayout() }
    }

    private func nextLayout() {
        guard layouts.count > 1 else { return }
        showsDigits = false
        layoutIndex = (layoutIndex + 1) % layouts.count
    }
}

// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The list AutoFill shows when the person asks Pesto for text: Pinned, Snippets and Recent, with a search.
struct InsertPickerView: View {
    let menu: QuickInsertMenu
    let insert: (QuickInsertEntry) -> Void
    var insertText: ((String) -> Void)?
    @State private var showsSettingsPlace = false
    let cancel: () -> Void
    @State private var query = ""
    @State private var activeChip: QuickInsertMenu.Chip = .all
    @State private var pendingFill: PendingSnippetFill?
    @State private var rowWidth: CGFloat = 360
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    private var theme: WidgetSnapshot.Theme {
        menu.accent ?? .brand
    }

    private var resolvedAccent: Color {
        Color(hex: theme.accent(dark: colorScheme == .dark)) ?? BrandAccent.color
    }

    private var resolvedAccentLabel: Color {
        let hex = theme.accent(dark: colorScheme == .dark)
        return Color(hex: ContrastRatio.labelHex(onFill: hex)) ?? .white
    }

    private var ground: Color {
        Color(hex: theme.ground(dark: colorScheme == .dark))
            ?? Color(uiColor: .systemGroupedBackground)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Insert from Pesto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                    }
                    // AutoFill says where the settings are rather than opening Pesto: no API lets a credential
                    // provider open its app, and 4.4.1's room for keyboards does not cover it (ADR 0072).
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsSettingsPlace = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(Text("Settings"))
                    }
                }
        }
        .alert("Pesto Settings", isPresented: $showsSettingsPlace) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open Pesto, then Settings → Keyboard & AutoFill.")
        }
        .tint(resolvedAccent)
        .environment(\.pestoAccent, resolvedAccent)
        .environment(\.pestoAccentLabel, resolvedAccentLabel)
        .environment(\.pestoSurface, ground)
        .sheet(item: $pendingFill) { fill in
            AutoFillSnippetSheet(fill: fill) { expanded in
                pendingFill = nil
                if let insertText {
                    insertText(expanded)
                } else {
                    insert(fill.entry)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch menu.state {
        case .unavailable:
            ContentUnavailableView(
                "Nothing to Insert Yet",
                systemImage: "text.insert",
                description: Text("Open Pesto once so your clips are ready here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ground.ignoresSafeArea())
        case .locked:
            ContentUnavailableView(
                "Pesto is Locked",
                systemImage: "lock.fill",
                description: Text("Open Pesto and unlock to insert clips.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ground.ignoresSafeArea())
        case .empty:
            ContentUnavailableView(
                "No Text Clips",
                systemImage: "text.insert",
                description: Text("Your pinned and recent text clips appear here. Clips with secrets never do.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ground.ignoresSafeArea())
        case .ready:
            grid
        }
    }

    private var grid: some View {
        let groups = menu.groups(matching: query, chip: activeChip)
        let columnsCount = CardGridLayout.columnCount(
            width: rowWidth, isAccessibilitySize: typeSize.isAccessibilitySize
        )
        let cardWidth = CardGridLayout.cardWidth(rowWidth: rowWidth, columns: columnsCount)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: CardGridLayout.spacing, alignment: .top),
            count: columnsCount
        )
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: columns, spacing: CardGridLayout.spacing) {
                            ForEach(group.entries) { entry in
                                cardButton(entry, width: cardWidth)
                            }
                        }
                        .padding(.horizontal, CardGridLayout.margin)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .onGeometryChange(for: CGFloat.self) { max(0, $0.size.width - CardGridLayout.margin * 2) } action: {
            rowWidth = $0
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if menu.chips.count > 1 {
                chipBar
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("Clips only, never passwords")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(ground.opacity(0.92))
        }
        .background(ground.ignoresSafeArea())
        .overlay {
            if groups.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
    }

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(menu.chips, id: \.chip) { label in
                    let isActive = activeChip == label.chip
                    Button {
                        activeChip = label.chip
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: label.symbolName)
                                .font(.caption)
                            Text(label.title)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(MobileChipStyle(
                        isActive: isActive,
                        tint: label.color.isEmpty ? nil : Color(hex: label.color),
                        chipHeight: 30,
                        touchMinimum: 36
                    ))
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal, CardGridLayout.margin)
            .padding(.vertical, 8)
        }
        .background(ground.opacity(0.95))
    }

    private func cardButton(_ entry: QuickInsertEntry, width: CGFloat) -> some View {
        let face = CardFace.decide(.init(
            type: entry.kind,
            text: entry.text,
            isConcealed: false,
            isSecret: false,
            pictureAspect: nil,
            isAnimated: false,
            hasLinkPicture: false,
            isDark: colorScheme == .dark
        ))
        let metrics = CardMetrics(width: width, typeSize: typeSize)
        let title = CardFace.faceTitle(
            type: entry.kind,
            inCollection: activeChip != .all && entry.section == .collection,
            isConcealed: false,
            customTitle: entry.customTitle,
            ogTitle: entry.ogTitle
        )
        let isFillIn = needsFillIn(entry)
        let shape = RoundedRectangle(cornerRadius: CardGridLayout.cornerRadius, style: .continuous)
        let cardFill = colorScheme == .dark ? Color.white.opacity(0.10) : Color.white

        return Button { choose(entry) } label: {
            Color.clear
                .aspectRatio(CardGridLayout.aspectRatio, contentMode: .fit)
                .overlay {
                    cardFace(entry, face: face, title: title, metrics: metrics, isFillIn: isFillIn)
                }
                .clipShape(shape)
                .background {
                    shape.fill(cardFill)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.07), radius: 3, y: 1)
                }
                .overlay {
                    shape.strokeBorder(
                        Color.primary.opacity(contrast == .increased ? 0.45 : 0.14),
                        lineWidth: 0.75
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.label())
        .accessibilityValue(Self.detail(of: entry) ?? "")
        .accessibilityHint(isFillIn ? "Opens snippet fill-in" : "Inserts this clip")
    }

    @ViewBuilder
    private func cardFace(
        _ entry: QuickInsertEntry,
        face: CardFace,
        title: String?,
        metrics: CardMetrics,
        isFillIn: Bool
    )
    -> some View {
        switch face {
        case let .color(fill, ink):
            ColorCardFace(text: entry.text, fill: fill, ink: ink, metrics: metrics, title: title) {
                cardFooter(entry, ink: ink == .white ? .white : .black, isFillIn: isFillIn)
            }
        case let .largeText(points):
            framed(entry, title: title, isFillIn: isFillIn) {
                LargeTextBody(text: CardPreviewText.display(entry.text), points: points, metrics: metrics)
            }
        case let .link(link):
            framed(entry, title: title, isFillIn: isFillIn) {
                LinkBody(link: link, metrics: metrics, hasTitle: title != nil)
            }
        case .code:
            framed(entry, title: title, isFillIn: isFillIn) {
                PlainTextBody(text: entry.text, isCode: true, metrics: metrics, hasTitle: title != nil)
            }
        default:
            framed(entry, title: title, isFillIn: isFillIn) {
                PlainTextBody(text: entry.text, isCode: false, metrics: metrics, hasTitle: title != nil)
            }
        }
    }

    private func framed<Body: View>(
        _ entry: QuickInsertEntry,
        title: String?,
        isFillIn: Bool,
        @ViewBuilder body: () -> Body
    )
    -> some View {
        VStack(alignment: .leading, spacing: CardMetrics.footGap) {
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                body()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            cardFooter(entry, ink: .secondary, isFillIn: isFillIn)
        }
        .padding(CardMetrics.inset)
    }

    private func cardFooter(_ entry: QuickInsertEntry, ink: Color, isFillIn: Bool) -> some View {
        HStack(spacing: 4) {
            if entry.section == .pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
            } else if entry.expandsOnInsert {
                Image(systemName: isFillIn ? "curlybraces" : "text.badge.plus")
                    .font(.caption2)
            }
            if let source = entry.source, !source.isEmpty {
                Text(source)
                    .lineLimit(1)
            } else if isFillIn {
                Text("Fill-in")
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Text(entry.date, style: .relative)
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(ink)
    }

    private func needsFillIn(_ entry: QuickInsertEntry) -> Bool {
        insertText != nil
            && entry.expandsOnInsert
            && !TemplateExpander.fillsWithoutAsking(entry.text)
    }

    private static func detail(of entry: QuickInsertEntry) -> String? {
        let line = entry.text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty && $0 != entry.title }
        return line.map { String($0.prefix(QuickInsertPolicy.maxTitleCharacters)) }
    }

    private func choose(_ entry: QuickInsertEntry) {
        if insertText != nil,
           let plan = SnippetCopyPlan.plan(for: entry.text, isSnippet: entry.expandsOnInsert),
           plan.needsSheet
        {
            pendingFill = PendingSnippetFill(entry: entry, plan: plan)
            return
        }
        insert(entry)
    }
}

private struct PendingSnippetFill: Identifiable {
    let entry: QuickInsertEntry
    let plan: SnippetCopyPlan
    var id: UUID {
        entry.id
    }
}

private struct AutoFillSnippetSheet: View {
    let fill: PendingSnippetFill
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fills: SnippetFills
    @FocusState private var focusedFieldID: String?

    init(fill: PendingSnippetFill, onInsert: @escaping (String) -> Void) {
        self.fill = fill
        self.onInsert = onInsert
        _fills = State(initialValue: SnippetFills.initial(
            for: fill.plan.fields,
            remembered: fill.entry.fieldMemory ?? [:]
        ))
    }

    private var textFieldIDs: [String] {
        fill.plan.fields.compactMap {
            if case .text = $0.kind { return $0.id }
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(fill.plan.fields) { field in
                        switch field.kind {
                        case let .text(multiline):
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                TextField(
                                    field.defaultValue ?? field.label,
                                    text: Binding(
                                        get: { fills.values[field.id] ?? "" },
                                        set: { fills.values[field.id] = $0 }
                                    ),
                                    axis: multiline ? .vertical : .horizontal
                                )
                                .lineLimit(multiline ? 1...6 : 1...1)
                                .accessibilityLabel(field.label)
                                .focused($focusedFieldID, equals: field.id)
                                .submitLabel(multiline ? .return : .done)
                                .onSubmit {
                                    guard !multiline else { return }
                                    insertExpanded()
                                }
                            }
                        case let .choice(choices):
                            Picker(field.label, selection: Binding(
                                get: { fills.values[field.id] ?? choices.first ?? "" },
                                set: { fills.values[field.id] = $0 }
                            )) {
                                ForEach(choices, id: \.self) { choice in
                                    Text(choice).tag(choice)
                                }
                            }
                        case .optional:
                            Toggle(field.label, isOn: Binding(
                                get: { fills.included.contains(field.id) },
                                set: { included in
                                    if included {
                                        fills.included.insert(field.id)
                                    } else {
                                        fills.included.remove(field.id)
                                    }
                                }
                            ))
                        }
                    }
                }
            }
            .onAppear {
                focusedFieldID = textFieldIDs.first
            }
            .navigationTitle(fill.entry.label())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert", action: insertExpanded)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }

    private func insertExpanded() {
        let expanded = fill.plan.expanded(
            fill.entry.text, fills: fills, pastedClipboard: "", at: .now
        )
        onInsert(expanded)
    }
}

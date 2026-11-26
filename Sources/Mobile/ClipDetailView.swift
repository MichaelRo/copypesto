// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// One clip whole, in a sheet on a compact width and in the inspector on a regular one: its content at full size, its
/// title, note and tags edited in place, its collection and one line of facts, with Copy and Share in the toolbar.
struct ClipDetailView: View {
    let store: HistoryStore
    let itemID: UUID
    let isSheet: Bool

    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.pestoSurface) private var ground
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var content: ClipContent?
    @State private var revealedText: String?
    @State private var similarIDs: [UUID] = []
    @State private var familyProposal: String?

    var body: some View {
        NavigationStack {
            Group {
                if let item = store.item(for: itemID) {
                    detail(item)
                } else {
                    ContentUnavailableView("Clip Deleted", systemImage: "trash")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) { if isSheet { LibraryBanners(messagesOnly: true) } }
            .clipResultSheets(.detail(isSheet: isSheet))
            .collectionImportConfirmation(
                active: isSheet && !library.showsSettings && appState.pendingFill == nil
                    && library.snippetEditor == nil && appState.decodedJWT == nil && !appState.showsAI
            )
            .sheet(item: fillBinding) { request in
                SnippetFillSheet(request: request).presentationDetents([.medium, .large])
            }
            .sheet(item: snippetEditorBinding) { target in
                MobileSnippetEditorView(target: target)
            }
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) {
                UITestLayout.swapControl(
                    library: library, actual: sizeClass, identifier: UITestLayout.detailSwapIdentifier
                )
                .padding(.top, 56)
                .padding(.trailing, 16)
            }
        #endif
    }

    private var fillBinding: Binding<SnippetFillRequest?> {
        Binding(get: { isSheet ? appState.pendingFill : nil }, set: { appState.pendingFill = $0 })
    }

    private var snippetEditorBinding: Binding<LibraryModel.SnippetEditorTarget?> {
        Binding(get: { isSheet ? library.snippetEditor : nil }, set: { library.snippetEditor = $0 })
    }

    private func detail(_ item: ClipboardItem) -> some View {
        let concealment = appState.secretReveal.concealment(for: item)
        return detailScroll(item, concealment: concealment)
            .background(ground.ignoresSafeArea())
            .accessibilityIdentifier(MobileAccessibilityID.clipDetail)
            .navigationTitle(item.type.presentation.label)
            .toolbar { toolbar(item, concealment: concealment) }
            .task(id: TaskKey(id: item.id, covered: concealment.isConcealed, content: item.contentHash)) {
                await reloadDetail(for: item, concealment: concealment)
            }
            .onChange(of: appState.secretReveal.isShown(item.id)) { _, shown in
                if !shown { library.endTextEdit() }
                guard let container = appState.historyContainer else { return }
                let id = item.id
                Task {
                    let loaded = await revealed(id, isShown: shown, container: container)
                    guard !Task.isCancelled, self.itemID == id, appState.secretReveal.isShown(id) == shown else {
                        return
                    }
                    revealedText = loaded
                }
            }
            .onChange(of: appState.isHistoryLocked) { _, locked in
                if locked { clearSensitiveDetailState() }
            }
            .onChange(of: itemID) { _, id in
                if !library.isEditingText(of: id) { library.endTextEdit() }
                clearSensitiveDetailState()
            }
    }

    private func detailScroll(_ item: ClipboardItem, concealment: CardConcealment) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isEditingText(item), content?.plainText != nil {
                    ClipTextEditor(item: item, onClose: { library.endTextEdit() }, draft: draftBinding)
                } else {
                    detailBodySection(item, concealment: concealment)
                }
                if item.sensitivityRaw != nil || (item.isNSFW && NSFWMode.current() != .show),
                   !appState.secretReveal.isCoveredForPrivacy(item.id)
                {
                    revealControl(item, concealment: concealment)
                }
                ClipDetailFields(item: item).id(item.id)
                AddToCollectionMenu(item: item, collections: collections)
                    .buttonStyle(MobileChipStyle(isActive: item.collectionID != nil, tint: nil))
                factsLine(item, concealment: concealment)
                similarClipsSection(for: item, concealment: concealment)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.peerDeviceNames, appState.peerDeviceNames)
            .environment(\.sourceAppCatalog, appState.sourceApps)
            .animation(Motion.animation(.pestoQuick), value: isEditingText(item))
        }
    }

    @ViewBuilder
    private func detailBodySection(_ item: ClipboardItem, concealment: CardConcealment) -> some View {
        if let text = content?.plainText {
            if appState.canEditSnippet(item) {
                Button("Edit Snippet\u{2026}", systemImage: "curlybraces") {
                    library.beginSnippetEdit(of: item, text: text)
                }
                .accessibilityIdentifier(MobileAccessibilityID.editSnippetButton)
            } else if appState.canEditText(item) {
                Button("Edit Text", systemImage: "pencil") {
                    library.beginTextEdit(of: item.id, text: text)
                }
                .accessibilityIdentifier(MobileAccessibilityID.editTextButton)
            }
        }
        ClipBodyView(item: item, content: content, concealment: concealment, revealedText: revealedText)
            .accessibilityIdentifier(MobileAccessibilityID.clipDetailBody)
    }

    private func clearSensitiveDetailState() {
        library.endTextEdit()
        similarIDs = []
        familyProposal = nil
        content = nil
        revealedText = nil
    }

    private func reloadDetail(for item: ClipboardItem, concealment: CardConcealment) async {
        clearSensitiveDetailState()
        let id = item.id
        guard !concealment.isConcealed, !appState.isHistoryLockedNow(),
              let container = appState.historyContainer else
        {
            clearSensitiveDetailState()
            return
        }
        content = item.type == .image ? nil : await ClipContent.load(itemID: id, container: container)
        revealedText = await revealed(id, isShown: appState.secretReveal.isShown(id), container: container)
        await loadSimilarClips(for: item)
    }

    private func isEditingText(_ item: ClipboardItem) -> Bool {
        library.isEditingText(of: item.id)
    }

    private var draftBinding: Binding<String> {
        Binding(get: { library.textEdit?.draft ?? "" }, set: { library.textEdit?.draft = $0 })
    }

    private func revealed(_ id: UUID, isShown: Bool, container: ModelContainer) async -> String? {
        guard isShown else { return nil }
        return await HiddenClipReveal.readableText(from: ClipContent.payload(itemID: id, container: container))
    }

    private struct TaskKey: Hashable {
        let id: UUID
        let covered: Bool
        let content: String
    }

    private func factsLine(_ item: ClipboardItem, concealment: CardConcealment) -> some View {
        let name = item.collectionID.flatMap { id in collections.first { $0.id == id }?.name }
        let line = ClipFacts.line(
            for: item, collectionName: name, isShown: !concealment.isConcealed,
            peerDeviceNames: appState.peerDeviceNames
        )
        return Text(line)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func similarClipsSection(for item: ClipboardItem, concealment: CardConcealment) -> some View {
        let candidates = safeSimilarItems()
        if !concealment.isConcealed, !appState.isHistoryLocked, isSimilarAnchorEligible(item), !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Similar Clips")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        saveAsSnippetButton
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Similar Clips")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        saveAsSnippetButton
                    }
                }
                ForEach(candidates, id: \.id) { match in
                    let matchConcealment = appState.secretReveal.concealment(for: match)
                    let summary = ClipSummary.make(match, concealment: matchConcealment)
                    Button {
                        library.open(match.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: match.type.presentation.symbolName)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.title)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let detail = summary.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            .quaternary.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityIdentifier(MobileAccessibilityID.similarClipsSection)
        }
    }

    private func safeSimilarItems() -> [ClipboardItem] {
        similarIDs.compactMap { id in
            guard let candidate = store.item(for: id),
                  !candidate.analysisPending,
                  candidate.sensitivityRaw == nil,
                  !candidate.isNSFW,
                  !appState.secretReveal.concealment(for: candidate).isConcealed else { return nil }
            return candidate
        }
    }

    @ViewBuilder
    private var saveAsSnippetButton: some View {
        if let proposal = familyProposal {
            Button("Save as Snippet\u{2026}", systemImage: "curlybraces") {
                library.beginNewSnippet(initialText: proposal)
            }
            .font(.footnote)
        }
    }

    private func isSimilarAnchorEligible(_ item: ClipboardItem) -> Bool {
        !item.analysisPending && item.sensitivityRaw == nil && !item.isNSFW
            && (item.type == .text || item.type == .code)
    }

    private func loadSimilarClips(for item: ClipboardItem) async {
        guard !appState.isHistoryLockedNow(),
              isSimilarAnchorEligible(item),
              !appState.secretReveal.concealment(for: item).isConcealed,
              let service = appState.storageService else
        {
            similarIDs = []
            familyProposal = nil
            return
        }
        let matches = await service.lookalikes(of: item.id)
        guard !Task.isCancelled,
              !appState.isHistoryLockedNow(),
              isSimilarAnchorEligible(item),
              !appState.secretReveal.concealment(for: item).isConcealed else
        {
            similarIDs = []
            familyProposal = nil
            return
        }
        let safeMatches: [ClipboardItem] = matches.compactMap { match in
            guard let candidate = store.item(for: match.id),
                  !candidate.analysisPending,
                  candidate.sensitivityRaw == nil,
                  !candidate.isNSFW,
                  !appState.secretReveal.concealment(for: candidate).isConcealed else { return nil }
            return candidate
        }
        similarIDs = Array(safeMatches.prefix(5).map(\.id))
        let texts = [item.displayPreviewText] + safeMatches.prefix(8).map(\.displayPreviewText)
        familyProposal = texts.count >= 2 ? TemplateInferrer.propose(from: texts)?.template : nil
    }

    @ViewBuilder
    private func revealControl(_ item: ClipboardItem, concealment: CardConcealment) -> some View {
        if item.sensitivityRaw != nil {
            if appState.secretReveal.isShown(item.id) {
                Button("Hide", systemImage: "eye.slash") { appState.secretReveal.hide(item.id) }
            } else if appState.secretReveal.canAuthenticate {
                Button("Show", systemImage: "eye") {
                    let id = item.id
                    Task { await appState.secretReveal.show(id, reason: String(localized: "Show the hidden clip")) }
                }
            } else {
                Text("Set a passcode on this device to show hidden clips. Copy still works.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if item.isNSFW, NSFWMode.current() != .show {
            if !concealment.isNSFWBlurred, appState.secretReveal.isNSFWShown(item.id) {
                Button("Hide", systemImage: "eye.slash") { appState.secretReveal.hideNSFW(item.id) }
            } else {
                Button("Show", systemImage: "eye") { appState.secretReveal.showNSFW(item.id) }
            }
        }
    }

    @ViewBuilder
    private func share(_ item: ClipboardItem, concealment: CardConcealment) -> some View {
        if concealment.isConcealed {
            EmptyView()
        } else if item.type == .image, let container = appState.historyContainer {
            ShareLink(
                item: DeferredPictureTransfer(
                    itemID: item.id, container: container, isGIF: item.mimeType?.contains("gif") == true
                ),
                preview: SharePreview(item.type.presentation.label)
            )
        } else if let content {
            ShareLink(item: ClipTransfer(content: content), preview: SharePreview(item.type.presentation.label))
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ item: ClipboardItem, concealment: CardConcealment) -> some ToolbarContent {
        if isSheet {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { library.openClipID = nil }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc") {
                Task {
                    if await appState.copyAsync(item) { library.didCopy(item.id) }
                }
            }
            .accessibilityIdentifier(MobileAccessibilityID.copyButton)
            share(item, concealment: concealment)
            Menu("More", systemImage: "ellipsis") {
                if !concealment.isConcealed, item.type == .url,
                   case let .openInBrowser(url) = LinkOpenPolicy.action(for: item.displayPreviewText)
                {
                    Button("Open Link", systemImage: "safari") { appState.openExternally(url) }
                }
                Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                    let id = item.id
                    Task { await appState.togglePin(id) }
                }
                CopyActionsMenu(item: item)
                AIActionsMenu(item: item)
                if !concealment.isConcealed, item.sensitivityRaw == nil, item.type == .image || item.type == .url {
                    Button(
                        item.isNSFW ? "Mark as Not Sensitive" : "Mark as Sensitive",
                        systemImage: item.isNSFW ? "eye" : "eye.slash"
                    ) {
                        appState.secretReveal.hideNSFW(item.id)
                        appState.toggleSensitive(item)
                    }
                }
                if appState.canEditSnippet(item), let text = content?.plainText {
                    Button("Edit Snippet\u{2026}", systemImage: "curlybraces") {
                        library.beginSnippetEdit(of: item, text: text)
                    }
                }
                if appState.canMakeSnippet(item), let text = content?.plainText {
                    Button("Make Snippet\u{2026}", systemImage: "text.badge.plus") {
                        library.beginMakeSnippet(of: item, text: text)
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    let id = item.id
                    library.openClipID = nil
                    Task { await appState.delete([id]) }
                }
            }
        }
    }
}

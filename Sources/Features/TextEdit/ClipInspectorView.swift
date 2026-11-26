// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The Clip Inspector (ADR 0071): the clip on the left, its title above it and its text editable when Edit Text would
/// be; its details on the right, each saved as it is changed and recorded for Undo through `ClipEditor`.
struct ClipInspectorView: View {
    let model: TextEditModel
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var matches: [ClipboardItem]
    @Query(sort: \Pinboard.sortOrder) private var pinboards: [Pinboard]
    @AppStorage(Setting.screenSharingPrivacy) private var screenSharingPrivacy: Bool
    @AppStorage(Setting.nsfwMode) private var nsfwModeRaw: String

    init(model: TextEditModel) {
        self.model = model
        let id = model.clipID
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        _matches = Query(descriptor)
    }

    var body: some View {
        let item = matches.first.flatMap { $0.isDeleted ? nil : $0 }
        let editor = appState.clipEditor(context: modelContext)
        Group {
            if appState.isContentCovered(screenSharingPrivacy: screenSharingPrivacy) {
                // A screen share or Hide Clip Contents covers the whole window, title and details too; a typed draft
                // waits in the model.
                ClipInspectorCover { model.cancel() }
            } else {
                HStack(spacing: 0) {
                    TextEditView(
                        model: model, item: item, editor: editor, showsPreview: item.map(showsPreview) ?? false,
                        showsPersonalDetails: item.map(showsPersonalDetails) ?? false
                    )
                    if let item {
                        Divider()
                        ClipDetailsPane(
                            item: item, editor: editor, collections: pinboards.filter { !$0.isSmart },
                            showsNote: showsPersonalDetails(item)
                        )
                        .frame(width: 270)
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 380)
    }

    /// The window is a way of showing a clip, so it obeys the card's cover (`CardConcealment`, AGENTS.md): a picture
    /// the content filter blurs, a hidden secret or a clip still being judged shows its facts only.
    private func showsPreview(_ item: ClipboardItem) -> Bool {
        CardConcealment(
            screenShareBlur: false,
            nsfwBlurred: item.isNSFW && (NSFWMode(rawValue: nsfwModeRaw) ?? .blur).blursCards,
            maskedSecret: item.sensitivity != nil, secretShown: model.isEditable,
            pendingAnalysis: item.analysisPending && item.type != .image
        ).allowsHoverDetail
    }

    /// A hidden secret's title and note stay hidden too, as on its hover card.
    private func showsPersonalDetails(_ item: ClipboardItem) -> Bool {
        item.sensitivity == nil || model.isEditable
    }
}

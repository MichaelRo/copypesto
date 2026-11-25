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

    init(model: TextEditModel) {
        self.model = model
        let id = model.clipID
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        _matches = Query(descriptor)
    }

    var body: some View {
        let item = matches.first
        let editor = appState.clipEditor(context: modelContext)
        HStack(spacing: 0) {
            TextEditView(model: model, item: item, editor: editor)
            if let item {
                Divider()
                ClipDetailsPane(item: item, editor: editor, collections: pinboards.filter { !$0.isSmart })
                    .frame(width: 270)
            }
        }
        .frame(minWidth: 620, minHeight: 380)
    }
}

// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The Clip window's root: it puts the history's container above `ClipInspectorView`, whose `@Query` reads it from its
/// ancestors (a container set on the querying view itself returns nothing).
struct ClipInspectorRoot: View {
    let model: TextEditModel
    @Environment(AppState.self) private var appState

    var body: some View {
        if let container = appState.historyContainer {
            ClipInspectorView(model: model)
                .id(model.clipID)
                .modelContainer(container)
        } else {
            TextEditView(model: model, item: nil, editor: nil)
        }
    }
}

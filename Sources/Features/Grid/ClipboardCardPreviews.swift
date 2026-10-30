// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

#if DEBUG
    @MainActor @ViewBuilder
    private func previewCard(
        _ type: ClipboardType, text: String, sensitivity: SensitivityCategory? = nil, mask: String? = nil
    )
    -> some View {
        if let container = try? ModelContainerSetup.makeInMemory() {
            ClipboardCard(item: ClipboardItem(
                type: type, previewText: mask ?? text, sensitivity: sensitivity, sensitivityMaskedPreview: mask,
                contentHash: UUID().uuidString, byteSize: text.utf8.count, deviceID: "preview", sequenceNumber: 1
            ))
            .frame(width: 220, height: 200)
            .padding(20)
            .modelContainer(container)
        } else {
            Text("The preview store did not open")
        }
    }

    #Preview("A text clip with no actions: a plain card") {
        previewCard(.text, text: "Quarterly numbers for the board")
    }

    #Preview("A link, with the menu commands the shelf supplies") {
        previewCard(.url, text: "example.com/launch-notes")
            .environment(\.cardActions, CardActions(copy: { _ in }, delete: { _ in }))
    }

    #Preview("A hidden secret") {
        previewCard(.text, text: "sk-live-0123456789", sensitivity: .apiKey, mask: "•••• (18 characters hidden)")
    }
#endif

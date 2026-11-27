// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Focused quick-look preview for a clip on iPhone and iPad, symmetric with Quick Look on macOS.
/// Never displays concealed, secret, or locked content, and offers a direct jump to Edit Details.
struct ClipPreviewView: View {
    let store: HistoryStore
    let itemID: UUID

    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.pestoSurface) private var ground
    @State private var content: ClipContent?

    var body: some View {
        NavigationStack {
            Group {
                if appState.isHistoryLocked {
                    ContentUnavailableView("History Locked", systemImage: "lock")
                } else if let item = store.item(for: itemID) {
                    preview(for: item)
                } else {
                    ContentUnavailableView("Clip Deleted", systemImage: "trash")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func preview(for item: ClipboardItem) -> some View {
        let concealment = appState.secretReveal.concealment(for: item)
        let allowed = item.sensitivityRaw == nil && !concealment.isConcealed
        return Group {
            if !allowed {
                ContentUnavailableView("Clip Hidden", systemImage: "eye.slash")
            } else if item.type == .image {
                ClipThumbnail(
                    itemID: item.id, byteSize: item.byteSize, maxPixel: 2048,
                    accessibilityText: PictureLabel.make(
                        width: item.pixelWidth, height: item.pixelHeight,
                        recognizedText: RecognizedText.hasText(item) ? item.displayPreviewText : nil
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    ClipBodyView(item: item, content: content, concealment: concealment, revealedText: nil)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(ground.ignoresSafeArea())
        .navigationTitle(item.type.presentation.label)
        .toolbar { toolbar(item, concealment: concealment) }
        .task(id: "\(item.id.uuidString):\(concealment.isConcealed)") {
            guard allowed, item.type != .image, !appState.isHistoryLockedNow(),
                  let container = appState.historyContainer else
            {
                content = nil
                return
            }
            content = await ClipContent.load(itemID: item.id, container: container)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ item: ClipboardItem, concealment: CardConcealment) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { library.previewClipID = nil }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc") {
                Task {
                    if await appState.copyAsync(item) { library.didCopy(item.id) }
                }
            }
            if !concealment.isConcealed, item.sensitivityRaw == nil {
                if item.type == .image, let container = appState.historyContainer {
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
            Button("Edit Details", systemImage: "info.circle") {
                library.open(item.id)
            }
        }
    }
}

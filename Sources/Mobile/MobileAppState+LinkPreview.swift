// SPDX-License-Identifier: MIT
import PestoCore

/// A link card's page title and picture, fetched once when the card is first on screen, under the Link Previews switch
/// (ADR 0005) and never while the history is locked.
extension MobileAppState {
    func loadLinkPreview(for item: ClipboardItem) async -> Bool {
        guard let container = historyContainer else { return false }
        let editor = clipEditor(context: container.mainContext)
        return await linkPreviewLoader.load(item, isHistoryLocked: isHistoryLockedNow(), editor: editor)
    }
}

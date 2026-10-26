// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData

extension AppState {
    static func beginWrite(on pb: NSPasteboard, protected: Bool) {
        PasteboardProtection.beginWrite(on: pb, protected: protected)
    }

    static func isProtected(_ pb: NSPasteboard) -> Bool {
        PasteboardProtection.isProtected(types: (pb.types ?? []).map(\.rawValue))
    }

    /// A paste from the shelf or the quick menu counts, and moves the clip to the front of the history.
    func notePasted(_ item: ClipboardItem, in context: ModelContext) {
        item.pasteCount += 1
        item.timestamp = Date()
        attempt("Couldn’t save the change") { try context.saveOrRollback() }
    }

    /// The shelf's paste: the same record as `notePasted`, written by the storage actor so the main thread does not
    /// wait
    /// for a save between the key press and the paste. Without a storage service (a test, a first run) it is written
    /// here.
    func notePastedInBackground(_ item: ClipboardItem, in context: ModelContext) {
        shelfSuggestionDwellTask?.cancel()
        shelfSuggestionDwellTask = nil
        shelfPasteTally[item.id, default: 0] += 1
        guard let service = storageService else { return notePasted(item, in: context) }
        let id = item.id
        Task {
            await attempt("Couldn\u{2019}t save the change") { _ = try await service.notePasted(id: id) }
        }
    }

    /// A copy from the shelf is a use of the clip too, so it moves to the front like a paste does. It is not counted as
    /// a paste: the person pastes it later, in an app, without Pesto.
    func noteCopied(_ item: ClipboardItem, in context: ModelContext) {
        item.timestamp = Date()
        attempt("Couldn’t save the change") { try context.saveOrRollback() }
    }

    /// An AI answer made from this clip was pasted: the clip moves to the front, as a paste of the clip itself does.
    /// Not noted when the person still has to press ⌘V, because nothing was pasted yet.
    func noteAnswerPasted(from itemID: UUID) async {
        await attempt("Couldn\u{2019}t move the clip to the front") {
            _ = try await storageService?.notePasted(id: itemID)
        }
    }

    /// Takes a pasted secret off the pasteboard after `secretClearDelay`, unless something else was copied meanwhile.
    /// Password managers do the same; without it the secret stays for any app, or any clipboard manager that ignores
    /// the concealed marker, to read until the next copy.
    func scheduleSecretClear() {
        secretClearTask?.cancel()
        let expected = AppPasteboard.general.changeCount
        secretClearTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: secretClearDelay)
            guard !Task.isCancelled, AppPasteboard.general.changeCount == expected else { return }
            writeToPasteboard { $0.clearContents() }
            if let current = self.activeStack?.current, current.isProtected {
                self.cancelActiveStack?()
            }
        }
    }

    /// Writes text that came from a clip (or from the live clipboard) back to the pasteboard, keeping the protection
    /// the source had.
    func writeText(_ text: String, protected: Bool) {
        writeToPasteboard { pb in
            Self.beginWrite(on: pb, protected: protected)
            pb.setString(text, forType: .string)
        }
        if protected { scheduleSecretClear() }
    }

    /// Writes an image back to the pasteboard through the write gate, keeping the protection the source had.
    func writeImage(_ image: NSImage, protected: Bool) {
        writeToPasteboard { pb in
            Self.beginWrite(on: pb, protected: protected)
            pb.writeObjects([image])
        }
        if protected { scheduleSecretClear() }
    }

    /// Writes the next clip of a paste stack. A secret is marked and, like every other paste of one, taken off the
    /// pasteboard again after `secretClearDelay`; a stack writes each clip as the one before is read, so the timer
    /// restarts with every secret and the last one is cleared too.
    func writeStackItem(_ item: PasteStack.Item) {
        guard !isHistoryLockedNow() else { return }
        writeToPasteboard { pb in
            Self.beginWrite(on: pb, protected: item.isProtected)
            if let data = item.pasteboardData, let typeStr = item.pasteboardType {
                item.richPayload?.write(to: pb)
                pb.setData(data, forType: NSPasteboard.PasteboardType(typeStr))
                if let plain = PasteFlavors.plainText(forStoredType: typeStr, data: data) {
                    pb.setString(plain, forType: .string)
                }
            } else {
                pb.setString(item.previewText, forType: .string)
            }
        }
        if item.isProtected { scheduleSecretClear() }
    }

    /// Copies a backup recovery key, concealed and cleared like a pasted secret.
    func copyRecoveryKey(_ key: String) {
        writeText(key, protected: true)
    }

    /// Writes the item to the pasteboard through the own-write gate and returns the payload the paste
    /// coordinator should use for its text tier. Returns nil, writing nothing, when the history is locked or the
    /// clip's saved data will not open (the person is told): the preview stands in only for a clip that never had
    /// data, such as a colour.
    @discardableResult
    func writeItem(_ item: ClipboardItem) -> PasteCoordinator.PayloadKind? {
        // Every route that puts a clip on the board ends here, so the lock is checked here as well as by the callers:
        // copy-only taps, number shortcuts and the context menu would otherwise skip it.
        guard !isHistoryLockedNow() else { return nil }
        let writing = PerfSignposts.paste.begin("writeItem")
        defer { writing.end() }
        let fileURLs = item.type == .file ? FileClip.urls(from: item.displayPreviewText) : []
        if FileClip.isGone(fileURLs) {
            attempt("Couldn’t paste this clip. Its files were moved or deleted.") { throw UnreadableClip() }
            showToast?(.filesGone)
            return nil
        }
        let plaintext = item.blob.map { $0.decryptedData() }
        if fileURLs.isEmpty, let readable = plaintext, readable == nil {
            attempt("Couldn’t paste this clip. Its saved data will not open.") { throw UnreadableClip() }
            return nil
        }
        let richPayload = item.blob?.decryptedRichPayload()
        clipboardBeforeLastItemWrite = ""
        if Self.needsLiveClipboard(item, data: plaintext.flatMap(\.self)) {
            clipboardBeforeLastItemWrite = AppPasteboard.general.string(forType: .string) ?? ""
        }
        defer { if item.sensitivityRaw != nil { scheduleSecretClear() } }
        let data = plaintext.flatMap(\.self)
        return writeToPasteboard { pb in
            Self.beginWrite(on: pb, protected: item.sensitivityRaw != nil)
            return ClipPasteboardWriter.fill(pb, with: item, fileURLs: fileURLs, data: data, richPayload: richPayload)
        }
    }

    /// Only a snippet whose text holds `{{clipboard}}` reads the board before it is overwritten; any other paste keeps
    /// nothing of what was on it (P-03).
    private static func needsLiveClipboard(_ item: ClipboardItem, data: Data?) -> Bool {
        guard item.isTemplate, let data, let text = String(data: data, encoding: .utf8) else { return false }
        return TemplateExpander.referencesClipboard(in: text)
    }

    private struct UnreadableClip: Error {}
}

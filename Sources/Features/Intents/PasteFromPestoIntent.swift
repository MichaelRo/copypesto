// SPDX-License-Identifier: MIT
import AppIntents
import AppKit
import PestoCore
import SwiftData

/// Finds a clipboard item whose preview text matches `search`, decrypts it, and
/// writes it to `AppPasteboard.general` so the user can ⌘V it immediately.
///
/// Returns the matched text so it can be used as input in a Shortcuts flow.
struct PasteFromPestoIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy from Pesto"
    static let description = IntentDescription(
        "Finds a clip matching the search text and copies it to the clipboard.",
        categoryName: "Clipboard"
    )

    @Parameter(title: "Search", description: "Text to search for in clipboard history.") var search: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (container, ownWrites): (ModelContainer, OwnWriteGate) = try await MainActor.run {
            guard
                let appState = ScriptingContext.appState,
                let c = appState.historyContainer else { throw PasteFromPestoError.notReady }
            guard ScriptingContext.historyIsAccessible else { throw PasteFromPestoError.locked }
            return (c, appState.ownWrites)
        }

        let ctx = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        let items = (try? ctx.fetch(descriptor)) ?? []
        let query = search
        // Clips holding a secret are masked on screen; a Shortcut must not be a way round the masking.
        guard let match = items.first(where: {
            $0.sensitivityRaw == nil && $0.displayPreviewText.localizedCaseInsensitiveContains(query)
        }) else {
            throw PasteFromPestoError.noMatch(query)
        }

        // Extract Sendable values from model objects before crossing actor boundaries.
        let preview = match.displayPreviewText
        let itemType = match.type
        struct BlobSnapshot: Sendable {
            let encryptedData: Data
            let nonceData: Data
            let mimeType: String
            let associatedData: Data?
        }
        let blobSnapshot: BlobSnapshot? = match.blob.map {
            BlobSnapshot(
                encryptedData: $0.encryptedData, nonceData: $0.nonceData, mimeType: $0.mimeType,
                associatedData: $0.associatedData
            )
        }

        let plain: Data? = blobSnapshot.flatMap {
            try? BlobEncryption().decrypt(
                BlobEncryption.EncryptedEnvelope(ciphertext: $0.encryptedData, nonce: $0.nonceData),
                associatedData: $0.associatedData
            )
        }

        await MainActor.run {
            ownWrites.write(to: AppPasteboard.general) { pb in
                pb.clearContents()
                if let p = plain, let snap = blobSnapshot {
                    pb.setData(p, forType: NSPasteboard.PasteboardType(snap.mimeType))
                } else {
                    pb.setString(preview, forType: .string)
                }
            }
        }

        if let p = plain, itemType == .text || itemType == .code, let str = String(data: p, encoding: .utf8) {
            return .result(value: str)
        }
        return .result(value: preview)
    }
}

private enum PasteFromPestoError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case locked
    case noMatch(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady:
            "Pesto is not ready. Open Pesto and try again."
        case .locked:
            "History is locked. Unlock Pesto first."
        case let .noMatch(query):
            "No clip matching \"\(query)\" was found."
        }
    }
}

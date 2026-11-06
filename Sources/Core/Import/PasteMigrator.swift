// SPDX-License-Identifier: MIT
import AppKit
import CryptoKit
import SwiftData

/// Imports items read from the Paste app (`PasteLibraryReader`) into Pesto.
///
/// Each record is routed through `StorageService.ingest` so encryption-at-rest, sensitivity
/// masking, and type classification apply identically to live capture — the migrator never
/// writes blobs directly. The ingested item is then pinned into a Collection whose name
/// matches the source pinboard (created on first use). Import is idempotent by content hash:
/// re-running never duplicates items. See `decisions/0011-read-only-surfaces.md`.
@ModelActor
public actor PasteMigrator {
    public struct Summary: Sendable, Equatable {
        public var imported: Int
        public var skipped: Int
        /// False when the import added more clips than one Undo holds (`UndoPolicy.maxClipsPerEntry`).
        public var isUndoable = true

        public init(imported: Int = 0, skipped: Int = 0) {
            self.imported = imported
            self.skipped = skipped
        }
    }

    /// An import that stopped part way (the library became unreadable, a save failed). What came in stays, is one Undo
    /// like a finished import, and is counted here, so the message can say so instead of "try again".
    public struct Interrupted: Error {
        public let summary: Summary
        public let cause: any Error
    }

    struct Run {
        var summary = Summary()
        var processedHashes = Set<String>()
        var addedIDs: [UUID] = []
        var createdBoards: [PinboardSnapshot] = []
        var key: SymmetricKey?
    }

    /// A record from an app on the exclusion list is skipped, as it would have been when copied: the list is how a
    /// person keeps a password manager's clips out of the history, and an import must not undo it.
    public func migrate(
        records: [PasteImportRecord],
        exclusionRules: ExclusionRules = ExclusionRules(),
        undoHistory: UndoHistory? = nil
    ) async throws
    -> Summary {
        let storage = StorageService(modelContainer: modelContainer)
        var run = Run()
        for record in records {
            try await process(record, exclusionRules: exclusionRules, storage: storage, run: &run)
        }
        return finish(run, undoHistory: undoHistory)
    }

    /// Imports the clips of `plan` from `snapshot` one group at a time, so a library of any size costs one group of
    /// memory. Between groups the work `ingest` leaves for later (judging pictures and long texts, computing search
    /// vectors) is waited for, which keeps that backlog to one group as well. Pinboards come first and history newest
    /// first, so an import cut short has already kept what matters most. The snapshot is discarded at the end.
    public func migrate(
        plan: PasteImportPlan,
        from snapshot: PasteLibrarySnapshot,
        includingHistory: Bool,
        exclusionRules: ExclusionRules = ExclusionRules(),
        undoHistory: UndoHistory? = nil,
        progress: (@Sendable (_ done: Int, _ total: Int) async -> Void)? = nil
    ) async throws
    -> Summary {
        let storage = StorageService(modelContainer: modelContainer)
        var run = Run()
        let total = plan.selectedCount(includingHistory: includingHistory)
        var done = 0
        do {
            for group in plan.batches(includingHistory: includingHistory) {
                let batch = try await snapshot.records(for: group[...])
                run.summary.skipped += batch.undecodable
                for record in batch.records {
                    try await process(record, exclusionRules: exclusionRules, storage: storage, run: &run)
                }
                await storage.waitForBackgroundWork()
                done += group.count
                await progress?(done, total)
            }
        } catch {
            await snapshot.discard()
            let partial = finish(run, undoHistory: undoHistory)
            throw partial.imported > 0 ? Interrupted(summary: partial, cause: error) : error
        }
        await snapshot.discard()
        return finish(run, undoHistory: undoHistory)
    }

    func finish(_ run: Run, undoHistory: UndoHistory?) -> Summary {
        var summary = run.summary
        let changed = !run.addedIDs.isEmpty || !run.createdBoards.isEmpty
        if run.addedIDs.count > UndoPolicy.maxClipsPerEntry { summary.isUndoable = false }
        if let undoHistory, changed, run.addedIDs.count <= UndoPolicy.maxClipsPerEntry {
            let added = AddedClips(kind: .imported, ids: run.addedIDs, boards: run.createdBoards)
            undoHistory.record(UndoEntry(.clipsAdded(added)))
        }
        return summary
    }

    /// One record through `StorageService.ingest`. A text over the size Pesto keeps is counted as left out like any
    /// other record that cannot come in, so one huge clip does not end a run of thousands.
    func process(
        _ record: PasteImportRecord,
        exclusionRules: ExclusionRules,
        storage: StorageService,
        run: inout Run
    ) async throws {
        let flattened = await Self.flattenedRichText(of: record)
        guard let capture = Self.makeCapture(from: record, flattenedRichText: flattened),
              !Self.isMarkedConcealed(record),
              !(record.sourceBundleID.map { exclusionRules.isExcluded($0) } ?? false),
              !Self.isTooLarge(capture) else
        {
            run.summary.skipped += 1
            return
        }
        // Collapse exact-duplicate content within a single run so `imported` reflects
        // distinct items, not raw record count.
        guard run.processedHashes.insert(capture.contentHash).inserted else {
            run.summary.skipped += 1
            return
        }

        let boardID: UUID? = if let pinboardName = record.pinboard {
            try collectionID(forPinboardNamed: pinboardName, created: &run.createdBoards)
        } else {
            nil
        }
        let key = try run.key ?? BlobEncryption().loadOrCreateKey()
        run.key = key
        let forms = ContentHash.candidates(for: capture.contentHash, key: key)
        let descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { forms.contains($0.contentHash) })
        let alreadyThere = try !modelContext.fetch(descriptor).isEmpty
        do {
            try await storage.ingest(capture)
        } catch is ClipSizePolicy.TooLarge {
            run.summary.skipped += 1
            return
        }

        // ingest deduplicates by content hash; fetch the resulting item (new or existing)
        // and attach it to the target collection.
        guard let item = try modelContext.fetch(descriptor).first else {
            run.summary.skipped += 1
            return
        }
        if let boardID {
            item.collectionID = boardID
            item.isPinned = true
        } else if record.title == FirstRunSamples.snippetTitle {
            item.isPinned = true
        }
        if let title = record.title, !title.isEmpty, item.customTitle == nil {
            item.customTitle = title
        }
        try modelContext.saveOrRollback()
        run.summary.imported += 1
        if !alreadyThere { run.addedIDs.append(item.id) }
    }

    private static func isTooLarge(_ capture: PasteboardCapture) -> Bool {
        ClipSizePolicy.isTooLarge(byteCount: capture.payload.count, typeIdentifier: capture.typeIdentifier)
    }

    /// The old app kept every flavour of a copy, markers included. One that said "concealed" or "transient" is dropped
    /// as the live watcher drops it (invariant 6), so an import cannot bring back a password the app never stored.
    static func isMarkedConcealed(_ record: PasteImportRecord) -> Bool {
        record.representations.contains { ExclusionRules.concealedTypeMarkers.contains($0.uti) }
    }

    /// The plain text of a record whose best representation is rich text and which has no plain-text copy. AppKit's
    /// rich-text import runs on the main actor, so it is read here, before `makeCapture`.
    static func flattenedRichText(of record: PasteImportRecord) async -> String? {
        let types = record.representations.map { NSPasteboard.PasteboardType($0.uti) }
        guard let selected = PasteboardTypeDetector.detect(types: types), selected == .rtf || selected == .rtfd,
              plainText(in: record) == nil,
              let base64 = record.representations.first(where: { $0.uti == selected.rawValue })?.dataBase64,
              let data = Data(base64Encoded: base64) else { return nil }
        return await RichTextFlattener.plainText(from: data, type: selected)
    }

    private static func plainText(in record: PasteImportRecord) -> String? {
        let plain = record.representations.first { $0.uti == NSPasteboard.PasteboardType.string.rawValue }
        guard let base64 = plain?.dataBase64, let data = Data(base64Encoded: base64),
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Builds a `PasteboardCapture` from a record's representations, selecting the primary
    /// type with the same priority order the live watcher uses. Rich text becomes its plain string, like a live
    /// copy (a stored RTF blob would be neither classified nor previewed). Returns nil when no supported
    /// representation is present or the record holds no text.
    static func makeCapture(from record: PasteImportRecord, flattenedRichText: String? = nil) -> PasteboardCapture? {
        let dataByType = Dictionary(
            record.representations.map { ($0.uti, $0.dataBase64) },
            uniquingKeysWith: { first, _ in first }
        )
        let types = record.representations.map { NSPasteboard.PasteboardType($0.uti) }
        guard let detected = PasteboardTypeDetector.detect(types: types) else { return nil }

        let selected: NSPasteboard.PasteboardType
        let payload: Data
        let payloadString: String?
        if detected == .rtf || detected == .rtfd {
            guard let text = plainText(in: record) ?? flattenedRichText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty else { return nil }
            selected = .string
            payload = Data(text.utf8)
            payloadString = text
        } else {
            guard let base64 = dataByType[detected.rawValue],
                  let data = Data(base64Encoded: base64), !data.isEmpty else { return nil }
            let stringTypes: Set<NSPasteboard.PasteboardType> = [.string, .URL, .fileURL]
            selected = detected
            payload = data
            payloadString = stringTypes.contains(detected) ? String(data: data, encoding: .utf8) : nil
        }
        let hash = payload.sha256Hex

        return PasteboardCapture(
            typeIdentifier: selected.rawValue,
            payload: payload,
            payloadString: payloadString,
            frontmostBundleID: record.sourceBundleID,
            timestamp: record.timestamp,
            contentHash: hash,
            richPayload: selected == .string ? richPayload(of: record) : nil
        )
    }

    /// The formatted flavours of a text record, with the live capture's size limit, so a pasted clip keeps its bold
    /// and links.
    private static func richPayload(of record: PasteImportRecord) -> RichTextPayload? {
        func flavour(_ type: NSPasteboard.PasteboardType) -> Data? {
            guard let base64 = record.representations.first(where: { $0.uti == type.rawValue })?.dataBase64,
                  let data = Data(base64Encoded: base64), !data.isEmpty,
                  data.count <= PasteboardWatcher.maxRichTextBytes else { return nil }
            return data
        }
        let payload = RichTextPayload(rtf: flavour(.rtf), rtfd: flavour(.rtfd), html: flavour(.html))
        return payload.isEmpty ? nil : payload
    }

    private func collectionID(forPinboardNamed name: String, created: inout [PinboardSnapshot]) throws -> UUID {
        let descriptor = FetchDescriptor<Pinboard>(predicate: #Predicate { $0.name == name })
        if let existing = try modelContext.fetch(descriptor).first { return existing.id }

        let style = Self.style(for: name)
        let maxOrder = try modelContext.fetch(FetchDescriptor<Pinboard>()).map(\.sortOrder).max() ?? -1
        let pinboard = Pinboard(
            name: name,
            symbolName: style.symbol,
            colorHex: style.color,
            sortOrder: maxOrder + 1
        )
        modelContext.insert(pinboard)
        try modelContext.saveOrRollback()
        created.append(PinboardSnapshot(pinboard))
        return pinboard.id
    }

    /// Maps Paste's default pinboard names onto sensible Pesto collection styling. Unknown
    /// names fall back to a neutral tray icon.
    private static func style(for name: String) -> (symbol: String, color: String) {
        switch name {
        case "Useful Links": ("link", "#4C8DFF")
        case "Useful Info": ("info.circle", "#34C759")
        case "Commands": ("terminal", "#AF52DE")
        case "Snippets": ("curlybraces", "#34C759")
        case "Prompts": ("text.bubble", "#FF9F0A")
        default: ("tray.full", "#8E8E93")
        }
    }
}

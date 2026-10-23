// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "DataSettings")

struct DataSettings: View {
    enum Part {
        case importExport, maintenance
    }

    let part: Part
    enum Action {
        case exportHistory, importHistory, importPaste, importSnippets, rebuildIndex
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState
    @State private var messages: [Action: String] = [:]
    @State private var isRebuildingIndex = false
    @State private var importPreview: ImportPreview?
    @State var otherFile: OtherFileChoice?

    var body: some View {
        switch part {
        case .importExport: importExportSection
        case .maintenance: maintenanceSection
        }
    }

    private var importExportSection: some View {
        Section {
            fileRow(
                "Text history",
                caption: LocalizedStringKey(
                    "A JSON file of your text, code, link and color clips. Not encrypted: secrets are masked, " +
                        "pictures and files are left out, and an import skips clips you already have."
                ),
                messages: [.exportHistory, .importHistory]
            ) {
                Button("Import\u{2026}", action: importHistory)
                    .accessibilityLabel("Import History")
                Button("Export\u{2026}", action: exportHistory)
                    .accessibilityLabel("Export Text Previews")
            }
            .settingsRow("Export clips")
            fileRow(
                "Another app\u{2019}s library",
                caption: LocalizedStringKey(
                    "Clips from another clipboard app, or snippets from a Raycast "
                        + "export. Pesto reads a copy and never changes the original. Your own clips stay."
                ),
                messages: [.importPaste, .importSnippets]
            ) {
                Menu("Import\u{2026}") {
                    Button("From Paste\u{2026}", action: importFromPaste)
                        .accessibilityIdentifier(AccessibilityID.importPasteButton)
                    Button("From Maccy\u{2026}") { importFromClipboardApp(.maccy) }
                        .accessibilityIdentifier(AccessibilityID.importMaccyButton)
                    Button("From Alfred\u{2026}") { importFromClipboardApp(.alfred) }
                        .accessibilityIdentifier(AccessibilityID.importAlfredButton)
                    Button("From CleanClip\u{2026}") { importFromClipboardApp(.cleanclip) }
                        .accessibilityIdentifier(AccessibilityID.importCleanClipButton)
                    Button("From PasteNow\u{2026}") { importFromClipboardApp(.pastenow) }
                        .accessibilityIdentifier(AccessibilityID.importPasteNowButton)
                    Button("From CopyClip\u{2026}") { importFromClipboardApp(.copyclip) }
                        .accessibilityIdentifier(AccessibilityID.importCopyClipButton)
                    Button("From PastePal\u{2026}") { importFromClipboardApp(.pastepal) }
                        .accessibilityIdentifier(AccessibilityID.importPastePalButton)
                    Button("From Pastebot\u{2026}") { importFromClipboardApp(.pastebot) }
                        .accessibilityIdentifier(AccessibilityID.importPastebotButton)
                    Button("From Clipy\u{2026}") { importFromClipboardApp(.clipy) }
                        .accessibilityIdentifier(AccessibilityID.importClipyButton)
                    Button("From Flycut\u{2026}") { importFromClipboardApp(.flycut) }
                        .accessibilityIdentifier(AccessibilityID.importFlycutButton)
                    Button("From Unclutter\u{2026}") { importFromClipboardApp(.unclutter) }
                        .accessibilityIdentifier(AccessibilityID.importUnclutterButton)
                    Button("Other File\u{2026}", action: importOtherFile)
                        .accessibilityIdentifier(AccessibilityID.importOtherFileButton)
                    Button("Snippets File\u{2026}", action: importSnippetsFile)
                        .accessibilityIdentifier(AccessibilityID.importSnippetsButton)
                }
                .menuStyle(.borderedButton)
                .fixedSize()
                .accessibilityLabel("Import from another app")
                .accessibilityIdentifier(AccessibilityID.importFromAppMenu)
            }
            .settingsRow("Import from another app")
        } header: {
            Text("Import and export")
        }
        .onChange(of: appState.pendingImportSource, initial: true) { _, source in
            guard let source else { return }
            appState.pendingImportSource = nil
            switch source {
            case .paste: importFromPaste()
            case .maccy: importFromClipboardApp(.maccy)
            case .alfred: importFromClipboardApp(.alfred)
            case .cleanclip: importFromClipboardApp(.cleanclip)
            case .pastenow: importFromClipboardApp(.pastenow)
            case .copyclip: importFromClipboardApp(.copyclip)
            case .pastepal: importFromClipboardApp(.pastepal)
            case .pastebot: importFromClipboardApp(.pastebot)
            case .clipy: importFromClipboardApp(.clipy)
            case .flycut: importFromClipboardApp(.flycut)
            case .unclutter: importFromClipboardApp(.unclutter)
            }
        }
        .sheet(item: $otherFile) { chosen in
            OtherFileSheet(
                fileName: chosen.name, file: chosen.file,
                onCancel: { otherFile = nil },
                onContinue: { library in
                    otherFile = nil
                    importPreview = ImportPreview(appName: chosen.name, library: library)
                }
            )
        }
        .sheet(isPresented: Binding(get: { importPreview != nil }, set: { if !$0 { importPreview = nil } })) {
            if let preview = importPreview {
                ImportPreviewSheet(
                    preview: preview,
                    retention: RetentionPolicy.fromDefaults(AppDefaults.store),
                    onCancel: { importPreview = nil },
                    onImport: { includeHistory in
                        importPreview = nil
                        runPasteImport(
                            preview.records(includingHistory: includeHistory),
                            librarySkipped: preview.skipped,
                            appName: preview.appName
                        )
                    }
                )
            }
        }
    }

    private var maintenanceSection: some View {
        Section {
            LabeledContent {
                HStack {
                    message(for: .rebuildIndex)
                    if isRebuildingIndex { ProgressView().controlSize(.small) }
                    Button("Rebuild") { rebuildSemanticIndex() }
                        .accessibilityLabel("Rebuild search index")
                        .disabled(isRebuildingIndex)
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Search index")
                    Text("Rebuilds the search index for text and code clips. It runs on this Mac; nothing is sent.")
                        .pestoCaption()
                }
            }
            .settingsRow("Rebuild search index")
        } header: {
            Text("Maintenance")
        }
    }

    private func fileRow(
        _ title: LocalizedStringKey, caption: LocalizedStringKey, messages actions: [Action],
        @ViewBuilder buttons: () -> some View
    )
    -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let action = actions.first(where: { messages[$0] != nil }) { message(for: action) }
                buttons()
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(caption).pestoCaption()
            }
        }
    }

    @ViewBuilder
    private func message(for action: Action) -> some View {
        if let text = messages[action] {
            Text(text)
                .pestoCaption()
        }
    }

    func flash(_ action: Action, _ text: String, seconds: Double = 3) {
        messages[action] = text
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if messages[action] == text { messages[action] = nil }
        }
    }

    private func exportHistory() {
        let container = modelContext.container
        Task {
            guard await ProtectedAction.permitted(reason: "Export your clipboard history") else {
                return flash(.exportHistory, "Not exported.")
            }
            do {
                let data = try await HistoryExporter(modelContainer: container).export()
                save(data, as: "pesto-history.json", flashing: .exportHistory)
            } catch {
                flash(.exportHistory, "Couldn’t export the history. Try another folder.")
            }
        }
    }

    private func importHistory() {
        guard let url = chooseJSONFile() else { return }
        let container = modelContext.container
        Task {
            guard await ProtectedAction.permitted(reason: "Import clips into your history") else {
                return flash(.importHistory, "Not imported.")
            }
            do {
                let count = try await HistoryExporter(modelContainer: container).importRecords(fromFile: url)
                flash(.importHistory, count == 0 ? "Nothing new." : String(localized: "\(count) clips imported."))
            } catch {
                flash(.importHistory, "Couldn’t import that file. Check that it is a Pesto export.")
            }
        }
    }

    private func importFromPaste() {
        Task {
            guard await ProtectedAction.permitted(reason: "Import clips from Paste") else {
                return flash(.importPaste, "Not imported.")
            }
            if let preview = ImportFixture.preview(forApp: "Paste", in: ImportFixture.requested) {
                return importPreview = preview
            }
            let panel = NSOpenPanel()
            let detected = PasteLibraryReader.existingDatabaseURL()
            panel.directoryURL = (detected ?? PasteLibraryReader.defaultDatabaseURL).deletingLastPathComponent()
            panel.nameFieldStringValue = "Paste.db"
            panel.message = "Choose Paste.db in the com.wiheads.paste folder. Pesto reads a copy and never changes it."
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let library = try await Task.detached { try PasteLibraryReader.read(databaseAt: url) }.value
                guard library.pinboardClipCount > 0 || !library.history.isEmpty else {
                    return flash(.importPaste, "No clips found in that file.")
                }
                importPreview = ImportPreview(paste: library)
            } catch PasteLibraryReader.ReadError.notAPasteLibrary {
                flash(.importPaste, "That is not a Paste library.", seconds: 5)
            } catch PasteLibraryReader.ReadError.tooLarge {
                flash(.importPaste, "That file is too large to import.", seconds: 5)
            } catch {
                flash(.importPaste, "Couldn’t read that file. Choose another one.", seconds: 5)
            }
        }
    }

    private func importFromClipboardApp(_ app: ClipboardAppSource) {
        Task {
            guard await ProtectedAction.permitted(reason: "Import clips from \(app.name)") else {
                return flash(.importPaste, "Not imported.")
            }
            if let preview = ImportFixture.preview(forApp: app.name, in: ImportFixture.requested) {
                return importPreview = preview
            }
            let panel = NSOpenPanel()
            panel.directoryURL = app.defaultDatabaseURL.deletingLastPathComponent()
            panel.nameFieldStringValue = app.defaultDatabaseURL.lastPathComponent
            panel.message = "Choose \(app.name)\u{2019}s library file. Pesto reads a copy and never changes it."
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = app.canChooseDirectories
            panel.treatsFilePackagesAsDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let library = try await Task.detached { try app.read(databaseAt: url) }.value
                guard !library.records.isEmpty else {
                    return flash(.importPaste, "No clips found in that file.", seconds: 5)
                }
                importPreview = ImportPreview(appName: app.name, library: library)
            } catch ClipboardAppLibraryReader.ReadError.notRecognized {
                flash(.importPaste, "That is not a \(app.name) library.", seconds: 5)
            } catch ClipboardAppLibraryReader.ReadError.tooLarge {
                flash(.importPaste, "That file is too large to import.", seconds: 5)
            } catch {
                flash(.importPaste, "Couldn’t read that file. Choose another one.", seconds: 5)
            }
        }
    }

    private func importSnippetsFile() {
        guard let url = chooseJSONFile() else { return }
        guard let data = try? Data(contentsOf: url) else { return flash(
            .importSnippets,
            "Couldn’t read that file. Choose another one."
        ) }
        let pack: SnippetPack
        do {
            pack = try SnippetPackReader.read(data)
        } catch SnippetPackReader.ReadError.tooLarge {
            return flash(.importSnippets, "That file is too large to import.", seconds: 5)
        } catch {
            return flash(.importSnippets, "That is not a snippets file.", seconds: 5)
        }
        guard !pack.snippets.isEmpty || !pack.plainText.isEmpty else {
            return flash(.importSnippets, "No snippets found in that file.", seconds: 5)
        }
        let service = appState.storageService ?? StorageService(modelContainer: modelContext.container)
        flash(.importSnippets, "Importing\u{2026}", seconds: 60)
        Task {
            let entries = (pack.snippets + pack.plainText).map { snippet -> (text: String, title: String?) in
                (snippet.text, snippet.name)
            }
            let added = await service.addSnippets(entries)
            flash(.importSnippets, snippetImportSummary(pack, added: added), seconds: 8)
        }
    }

    private func snippetImportSummary(_ pack: SnippetPack, added: Int) -> String {
        var parts = [String(localized: "\(min(added, pack.snippets.count)) snippets imported.")]
        if !pack.plainText.isEmpty {
            parts.append(String(localized: "\(pack.plainText.count) without a placeholder were pinned as clips."))
        }
        if pack.withUnsupportedTokens > 0 {
            parts.append(String(
                localized: "\(pack.withUnsupportedTokens) snippets have tokens Pesto does not fill in, left as typed."
            ))
        }
        return parts.joined(separator: " ")
    }

    private func importMessage(_ report: ImportReport) -> String {
        var parts = [
            report
                .imported == 0 ? String(localized: "Nothing new.") :
                String(localized: "\(report.imported) clips imported.")
        ]
        if report.skipped > 0 {
            parts
                .append(
                    String(
                        localized: "\(report.skipped) were left out (duplicates, excluded apps, unreadable)."
                    )
                )
        }
        if report.expiring > 0 {
            parts
                .append(
                    String(
                        localized: "\(report.expiring) of them are older than the Keep clips for limit and will go."
                    )
                )
        }
        return parts.joined(separator: " ")
    }

    private func runPasteImport(_ records: [PasteImportRecord], librarySkipped: Int = 0, appName: String? = nil) {
        let container = modelContext.container
        let undoHistory = appState.undoHistory
        flash(.importPaste, "Importing\u{2026}", seconds: 60)
        Task {
            do {
                let summary = try await PasteMigrator(modelContainer: container).migrate(
                    records: records, exclusionRules: ExclusionRules.fromSettings(), undoHistory: undoHistory
                )
                let report = ImportReport(
                    summary: summary, librarySkipped: librarySkipped, records: records,
                    retention: RetentionPolicy.fromDefaults(AppDefaults.store)
                )
                if let source = ImportSource.allCases.first(where: { $0.name == appName }) {
                    appState.importedThisSession[source, default: 0] += report.imported
                }
                flash(.importPaste, importMessage(report), seconds: report.skipped + report.expiring > 0 ? 14 : 6)
            } catch {
                logger.error("Paste import failed: \(error.localizedDescription, privacy: .public)")
                flash(.importPaste, "Couldn’t import from that library. Try again.", seconds: 5)
            }
        }
    }

    private func rebuildSemanticIndex() {
        isRebuildingIndex = true
        let container = modelContext.container
        let start = Date()
        Task {
            defer { isRebuildingIndex = false }
            do {
                let count = try await StorageService(modelContainer: container).rebuildSemanticIndex()
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                flash(
                    .rebuildIndex,
                    count == 0 ? "Nothing to index." : String(localized: "\(count) clips re-indexed.") +
                        " (\(elapsed) ms)",
                    seconds: 5
                )
            } catch {
                flash(.rebuildIndex, "Couldn’t rebuild the search index. Try again.", seconds: 5)
            }
        }
    }

    private func save(_ data: Data, as name: String, flashing action: Action) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PrivateFile.write(data, to: url)
            flash(action, "Saved.")
        } catch {
            flash(action, "Couldn’t save the file. Choose another folder.")
        }
    }

    private func chooseJSONFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

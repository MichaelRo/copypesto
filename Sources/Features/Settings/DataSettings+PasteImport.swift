// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

extension DataSettings {
    /// Touch ID, a file panel, then a read-only copy of the library that is planned from each clip's size and date
    /// alone, so a library of any size opens the sheet quickly and holds nothing (ADR 0032).
    func importFromPaste() {
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
            flash(.importPaste, "Reading\u{2026}", seconds: 120)
            do {
                let snapshot = try await Task.detached { try PasteLibrarySnapshot.open(databaseAt: url) }.value
                let existing = try await existingClips()
                let plan = try await snapshot.plan(
                    retention: RetentionPolicy.fromDefaults(AppDefaults.store), existing: existing
                )
                guard plan.libraryClips > 0 else {
                    await snapshot.discard()
                    return flash(.importPaste, "No clips found in that file.")
                }
                messages[.importPaste] = nil
                importPreview = ImportPreview(paste: plan, snapshot: snapshot)
            } catch PasteLibraryReader.ReadError.notAPasteLibrary {
                flash(.importPaste, "That is not a Paste library.", seconds: 5)
            } catch PasteLibraryReader.ReadError.notEnoughSpace {
                flash(
                    .importPaste,
                    "There is not enough free space to read that library. Free some and try again.",
                    seconds: 8
                )
            } catch {
                flash(.importPaste, "Couldn’t read that file. Choose another one.", seconds: 5)
            }
        }
    }

    /// The sheet is closed without importing: the copy of the library goes with it.
    func closePreview() {
        if let snapshot = importPreview?.snapshot { Task { await snapshot.discard() } }
        importPreview = nil
    }

    func importPlanned(_ preview: ImportPreview, includingHistory: Bool) {
        guard let plan = preview.plan, let snapshot = preview.snapshot else { return closePreview() }
        importPreview = nil
        let container = modelContext.container
        let undoHistory = appState.undoHistory
        let total = plan.selectedCount(includingHistory: includingHistory)
        flash(.importPaste, importingText(0, total), seconds: 3600)
        Task {
            do {
                let summary = try await PasteMigrator(modelContainer: container).migrate(
                    plan: plan, from: snapshot, includingHistory: includingHistory,
                    exclusionRules: ExclusionRules.fromSettings(), undoHistory: undoHistory
                ) { done, total in
                    Task { @MainActor in
                        messages[.importPaste] = importingText(done, total)
                    }
                }
                let report = ImportReport(
                    summary: summary, librarySkipped: preview.skipped, leftByLimits: leftByLimits(
                        plan,
                        includingHistory
                    ),
                    retention: RetentionPolicy.fromDefaults(AppDefaults.store)
                )
                if let source = ImportSource.allCases.first(where: { $0.name == preview.appName }) {
                    appState.importedThisSession[source, default: 0] += report.imported
                }
                flash(.importPaste, importMessage(report), seconds: 3600)
            } catch {
                dataSettingsLogger.error("Paste import failed: \(error.localizedDescription, privacy: .public)")
                flash(.importPaste, "Couldn’t import from that library. Try again.", seconds: 5)
            }
        }
    }

    private func importingText(_ done: Int, _ total: Int) -> String {
        String(localized: "Importing\u{2026} \(done.formatted()) of \(total.formatted())")
    }

    /// What stayed in Paste: the clips the limits left out and, when the person left the history out, the history the
    /// plan had room for.
    private func leftByLimits(_ plan: PasteImportPlan, _ includingHistory: Bool) -> Int {
        plan.leftByLimits + (includingHistory ? 0 : plan.history.count)
    }

    private func existingClips() async throws -> [ExistingClip] {
        guard let service = appState.storageService else { return [] }
        return try await StorageRetentionStore(service: service).retentionSnapshot(expiringBefore: .distantPast)
            .candidates
    }
}

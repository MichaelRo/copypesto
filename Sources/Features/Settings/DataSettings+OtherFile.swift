// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// The file the person chose in Other File…, read and waiting for its columns to be mapped.
struct OtherFileChoice: Identifiable {
    let id = UUID()
    let name: String
    let file: GenericFile
}

extension DataSettings {
    /// A file of clips from an app Pesto has no reader for: Touch ID, a file panel, a bounded read off the main thread,
    /// then the sheet that maps its columns (ADR 0011).
    func importOtherFile() {
        Task {
            guard await ProtectedAction.permitted(reason: "Import clips from a file") else {
                return flash(.importPaste, "Not imported.")
            }
            var name = ImportFixture.otherFileName
            var data = ImportFixture.otherFileCSV
            if ImportFixture.requested != "otherfile" {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .json, .plainText]
                panel.message = "Choose a CSV, JSON or text file of clips. Pesto reads a copy and never changes it."
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                guard size <= GenericFileReader.maxBytes else {
                    return flash(.importPaste, "That file is too large to import.", seconds: 5)
                }
                guard let read = try? await Task.detached(operation: { try Data(contentsOf: url) }).value else {
                    return flash(.importPaste, "Couldn’t read that file. Choose another one.", seconds: 5)
                }
                (name, data) = (url.lastPathComponent, read)
            }
            let fileExtension = (name as NSString).pathExtension
            do {
                let file = try await Task.detached { try GenericFileReader.read(data, fileExtension: fileExtension) }
                    .value
                guard file.format == .text || !file.rows.isEmpty else {
                    return flash(.importPaste, "No clips found in that file.", seconds: 5)
                }
                otherFile = OtherFileChoice(name: name, file: file)
            } catch {
                flash(.importPaste, "That does not look like a CSV, JSON or text file of clips.", seconds: 5)
            }
        }
    }
}

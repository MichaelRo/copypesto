// SPDX-License-Identifier: MIT
import Foundation

/// A clip dragged to the Desktop or a Finder window has to arrive as a file: those drops take files and file promises,
/// not the data representations a text field or an editor accepts. The file is written when the drop asks for it, owner
/// only, in a folder the launch and the history lock sweep (`QuickLookPreviewController.sweepStaleTempFiles`).
public enum DragFile {
    public static let folderPrefix = "pesto-drag-"

    public static func fileName(title: String?, date: Date, fileExtension: String) -> String {
        "\(ImageExport.baseName(title: title, date: date)).\(fileExtension)"
    }

    /// Writes `data` as `name` in a fresh folder under `directory` and returns the file, or nil when it cannot be
    /// written.
    public static func write(
        _ data: Data, named name: String, in directory: URL = FileManager.default.temporaryDirectory
    )
    -> URL? {
        let folder = directory.appendingPathComponent("\(folderPrefix)\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            let file = folder.appendingPathComponent(name)
            try PrivateFile.write(data, to: file)
            return file
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }
}

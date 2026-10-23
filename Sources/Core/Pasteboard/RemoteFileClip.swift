// SPDX-License-Identifier: MIT
import AppKit
import UniformTypeIdentifiers

/// What Pesto keeps of a file copied on another device. Universal Clipboard puts the file in a temporary folder that
/// macOS empties within seconds of the pasteboard changing, so a path to it is dead almost at once. A picture can be
/// kept as its bytes; any other file is not kept.
public enum RemoteFileClip {
    public struct Picture: Equatable, Sendable {
        public let type: NSPasteboard.PasteboardType
        public let data: Data
    }

    /// The one picture the board holds, or nil when it holds anything else (a PDF, text, several files, a picture
    /// format
    /// Pesto has no type for, a file that is gone or over the size limit, which is judged before the file is read).
    public static func picture(
        from urls: [URL],
        byteCount: (URL) -> Int? = { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        },
        read: (URL) -> Data? = { try? Data(contentsOf: $0) }
    )
        -> Picture?
    {
        guard urls.count == 1, let url = urls.first,
              let utType = UTType(filenameExtension: url.pathExtension), utType.conforms(to: .image) else { return nil }
        let type = NSPasteboard.PasteboardType(utType.identifier)
        guard PasteboardTypeDetector.clipboardType(for: type) == .image,
              let size = byteCount(url), size > 0,
              !ClipSizePolicy.isTooLarge(byteCount: size, typeIdentifier: utType.identifier),
              let data = read(url), !data.isEmpty else { return nil }
        return Picture(type: type, data: data)
    }
}

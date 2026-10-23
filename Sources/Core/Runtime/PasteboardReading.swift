// SPDX-License-Identifier: MIT
import AppKit

/// Minimal pasteboard protocol so we can drive the watcher from tests.
public protocol PasteboardReading: ChangeCounting, Sendable {
    var changeCount: Int { get }
    func types() -> [NSPasteboard.PasteboardType]
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    /// Every file on the board. A Finder copy of several files has one pasteboard item per file, and
    /// `data(forType:)` only reads the first.
    func fileURLs() -> [URL]
}

public extension PasteboardReading {
    func fileURLs() -> [URL] {
        PasteboardFiles.single(from: self)
    }
}

public enum PasteboardFiles {
    public static func single(from board: some PasteboardReading) -> [URL] {
        guard let data = board.data(forType: .fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return FileClip.urls(from: text)
    }
}

extension NSPasteboard: ChangeCounting {}

/// The part of a pasteboard `OwnWriteGate` needs. `NSPasteboard` is not `Sendable` and does not claim to be; code that
/// reads from several threads goes through `SystemPasteboard`.
public protocol ChangeCounting {
    var changeCount: Int { get }
}

// SPDX-License-Identifier: MIT
import AppKit
@testable import PestoCore

/// In-memory pasteboard double for testing the watcher.
final class FakePasteboard: PasteboardReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _changeCount = 0
    private var _types: [NSPasteboard.PasteboardType] = []
    private var _payloads: [NSPasteboard.PasteboardType: Data] = [:]
    private var _strings: [NSPasteboard.PasteboardType: String] = [:]
    private var _fileURLs: [URL]?
    private var _contentReads = 0

    var changeCount: Int {
        lock.withLock { _changeCount }
    }

    /// How many times the watcher asked for a copy's bytes, text or files (not its type list).
    var contentReads: Int {
        lock.withLock { _contentReads }
    }

    func types() -> [NSPasteboard.PasteboardType] {
        lock.withLock { _types }
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        lock.withLock {
            _contentReads += 1
            return _payloads[type]
        }
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        lock.withLock {
            _contentReads += 1
            return _strings[type]
        }
    }

    func fileURLs() -> [URL] {
        lock.withLock { _contentReads += 1 }
        return lock.withLock { _fileURLs } ?? PasteboardFiles.single(from: self)
    }

    /// A Finder copy of several files: one pasteboard item per file.
    func writeFiles(_ urls: [URL], alsoTypes: [NSPasteboard.PasteboardType] = []) {
        lock.withLock {
            _changeCount += 1
            _types = [.fileURL] + alsoTypes
            _payloads = [.fileURL: Data((urls.first?.absoluteString ?? "").utf8)]
            _strings = [.fileURL: urls.first?.absoluteString ?? ""]
            _fileURLs = urls
        }
    }

    func write(
        types: [NSPasteboard.PasteboardType],
        data: [NSPasteboard.PasteboardType: Data],
        strings: [NSPasteboard.PasteboardType: String] = [:]
    ) {
        lock.withLock {
            _changeCount += 1
            _types = types
            _payloads = data
            _strings = strings
            _fileURLs = nil
        }
    }
}

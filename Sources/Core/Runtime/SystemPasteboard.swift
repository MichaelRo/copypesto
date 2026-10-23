// SPDX-License-Identifier: MIT
import AppKit

/// One `NSPasteboard`, read from anywhere. Apple does not mark `NSPasteboard` `Sendable`, so it is wrapped here, not
/// declared so for everyone. The watcher reads it on its own actor while the app writes it on the main thread, which
/// is not a single-queue invariant. It holds because every individual call goes to the pasteboard server, which
/// serialises them, and `tick()` re-checks `changeCount` after each suspension to notice a write that landed in
/// between. This type only reads; the one place that writes keeps its `NSPasteboard` on the main actor.
public final class SystemPasteboard: PasteboardReading, @unchecked Sendable {
    private let board: NSPasteboard

    public init(_ board: NSPasteboard) {
        self.board = board
    }

    public var changeCount: Int {
        board.changeCount
    }

    public func types() -> [NSPasteboard.PasteboardType] {
        board.types ?? []
    }

    public func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        board.data(forType: type)
    }

    public func string(forType type: NSPasteboard.PasteboardType) -> String? {
        board.string(forType: type)
    }

    public func fileURLs() -> [URL] {
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls ?? []
    }

    @available(macOS 15.4, *)
    public var accessBehavior: NSPasteboard.AccessBehavior {
        board.accessBehavior
    }
}

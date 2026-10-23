// SPDX-License-Identifier: MIT
import AppKit

/// The single access point for the pasteboard Pesto watches and writes. Tests get a private named
/// pasteboard, so a run never reads or overwrites what the user has copied.
public enum AppPasteboard {
    /// For writers, which run on the main actor. `NSPasteboard` is not `Sendable`, so it stays there.
    @MainActor public static let general = make(for: RuntimeConfiguration.current)

    /// For readers that run anywhere (the watcher's actor, a notification handler): the same board, reads only.
    public static let reader = SystemPasteboard(make(for: RuntimeConfiguration.current))

    static func make(for configuration: RuntimeConfiguration) -> NSPasteboard {
        guard configuration.mode != .normal else { return .general }
        if configuration.mode == .uiTest, configuration.usesRealPasteboard { return .general }
        return NSPasteboard(name: NSPasteboard.Name(configuration.pasteboardName))
    }
}

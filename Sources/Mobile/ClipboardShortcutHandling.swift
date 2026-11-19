// SPDX-License-Identifier: MIT

@MainActor
protocol ClipboardShortcutHandling: Sendable {
    func addClipboardFromShortcut() async throws
}

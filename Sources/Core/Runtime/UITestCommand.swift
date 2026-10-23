// SPDX-License-Identifier: MIT
import Foundation

/// Commands a UI test sends to a running `-UITestMode` app in place of the global hotkeys, which are
/// never registered under test. Shared by the app and the UI-test runner.
public enum UITestCommand: String, CaseIterable, Sendable {
    case showOverlay
    case hideOverlay
    case showQuickMenu
    case togglePinnedWindow
    case openSettings
    case openSettingsAtData
    case showOnboarding
    case openAbout
    case toggleHideContents
    /// Shows the toast and keeps it up (it fades after 2.5 s otherwise), so the accessibility audit can measure it.
    case showToast
    /// Moves the focus along the shelf to its last clip in steps, so every card in between is drawn once; writes
    /// `walk-done` into the work directory when it arrives (`scripts/check-memory-budget.sh`).
    case walkShelfToEnd
    /// The person's own ⌘V while a paste stack runs; the global key monitor is not installed under test.
    case stackUserPaste
}

/// A directory-backed queue between the runner and the app. The runner is sandboxed and cannot post
/// distributed notifications, but it shares the working directory with the app, so commands travel as files.
public enum UITestCommandQueue {
    public static let directoryName = "commands"

    public static func enqueue(_ command: UITestCommand, in directory: URL) throws {
        let queue = directory.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        // Zero-padded monotonic clock so a lexical sort is the enqueue order across both processes.
        let stamp = String(format: "%020llu", DispatchTime.now().uptimeNanoseconds)
        let file = queue.appendingPathComponent("\(stamp)-\(UUID().uuidString).cmd")
        try Data(command.rawValue.utf8).write(to: file, options: .atomic)
    }

    public static func drain(in directory: URL) -> [UITestCommand] {
        let queue = directory.appendingPathComponent(directoryName, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: queue.path) else { return [] }
        var commands: [UITestCommand] = []
        for name in names.filter({ $0.hasSuffix(".cmd") }).sorted() {
            let file = queue.appendingPathComponent(name)
            if let data = try? Data(contentsOf: file),
               let raw = String(data: data, encoding: .utf8),
               let command = UITestCommand(rawValue: raw)
            {
                commands.append(command)
            }
            try? FileManager.default.removeItem(at: file)
        }
        return commands
    }
}

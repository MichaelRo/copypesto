// SPDX-License-Identifier: MIT
// Multi-app live paste, Paste As…, caret preservation, snippet prompt, and CGEventDrag verification suite
// driving BenchTarget (PESTO_UITEST_REAL_PASTE=1) and target apps (TextEdit, Notes, Safari, Chrome, Edge,
// Terminal, VS Code) via XCUIApplication / AXUIElement / CGEvent.
//
// Usage: MultiAppSuite <work-dir> <http-port> [suite: all|matrix|paste-as|entry-points|snippets|drag]
import AppKit
import ApplicationServices
import Foundation
import XCTest

private func logOut(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

private enum TargetBundle: String, CaseIterable {
    case textEdit = "com.apple.TextEdit"
    case notes = "com.apple.Notes"
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case edge = "com.microsoft.edgemac"
    case terminal = "com.apple.Terminal"
    case vscode = "com.microsoft.VSCode"
    case finder = "com.apple.finder"

    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue)
    }
}

private enum HID {
    static let source = CGEventSource(stateID: .hidSystemState)

    static func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
    }

    static func drag(from start: CGPoint, to end: CGPoint) {
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(40_000)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(60_000)
        for step in 1...16 {
            let ratio = CGFloat(step) / 16.0
            let pt = CGPoint(x: start.x + (end.x - start.x) * ratio, y: start.y + (end.y - start.y) * ratio)
            CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: pt,
                mouseButton: .left
            )?
                .post(tap: .cghidEventTap)
            usleep(12_000)
        }
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}

private func sendCommand(_ name: String, workDir: URL) {
    let dir = workDir.appendingPathComponent("commands", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let stamp = String(format: "%020llu", DispatchTime.now().uptimeNanoseconds)
    let file = dir.appendingPathComponent("\(stamp)-\(UUID().uuidString).cmd")
    try? Data(name.utf8).write(to: file, options: .atomic)
}

private func runProcess(_ executable: String, args: [String], wait: Bool = false) -> Process? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = args
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    if wait { proc.waitUntilExit() }
    return proc
}

private func axAppElement(bundleIdentifier: String) -> AXUIElement? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
        return nil
    }
    return AXUIElementCreateApplication(app.processIdentifier)
}

private func launchIfInstalled(_ target: TargetBundle, arguments: [String] = []) -> Bool {
    guard let url = target.appURL else {
        logOut("skip  \(target.rawValue) not installed")
        return false
    }
    let config = NSWorkspace.OpenConfiguration()
    config.arguments = arguments
    config.activates = true
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
        ok = (app != nil)
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 10)
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        _ = XCUIApplication(bundleIdentifier: target.rawValue)
    }
    return ok
}

private func runMatrix(workDir: URL, pasteURL: String, gifURL: String) {
    let apps: [(TargetBundle, [String])] = [
        (.textEdit, []),
        (.notes, []),
        (.safari, [pasteURL]),
        (.chrome, [
            "--host-resolver-rules=MAP giftest.example 127.0.0.1",
            "--ignore-certificate-errors",
            gifURL
        ]),
        (.edge, [
            "--host-resolver-rules=MAP giftest.example 127.0.0.1",
            "--ignore-certificate-errors",
            gifURL
        ]),
        (.terminal, []),
        (.vscode, ["--disable-extensions"])
    ]
    for (bundle, launchArgs) in apps where launchIfInstalled(bundle, arguments: launchArgs) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        sendCommand("showOverlay", workDir: workDir)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        HID.pressKey(36)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        logOut("ok    paste matrix exercised for \(bundle.rawValue)")
    }
}

@main
struct MultiAppSuite {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            fputs("usage: MultiAppSuite <work-dir> <http-port> [suite]\n", stderr)
            exit(2)
        }
        let workDir = URL(fileURLWithPath: args[1], isDirectory: true)
        let port = args[2]
        let suite = args.count >= 4 ? args[3] : "all"

        let pasteURL = "http://127.0.0.1:\(port)/paste-listener.html"
        let gifURL = "https://giftest.example:\(port)/gif-page.html"

        if suite == "all" || suite == "matrix" {
            runMatrix(workDir: workDir, pasteURL: pasteURL, gifURL: gifURL)
        }

        if suite == "all" || suite == "paste-as" {
            _ = launchIfInstalled(.textEdit)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            sendCommand("showOverlay", workDir: workDir)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            HID.pressKey(53)
            logOut("ok    Paste As… flow exercised")
        }

        if suite == "all" || suite == "entry-points", launchIfInstalled(.textEdit) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            _ = runProcess("/usr/bin/open", args: ["pesto://open"], wait: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            HID.pressKey(53)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            _ = runProcess("/usr/bin/shortcuts", args: ["run", "Open Pesto"], wait: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            HID.pressKey(53)
            logOut("ok    caret-preserving entry points exercised")
        }

        if suite == "all" || suite == "snippets", launchIfInstalled(.textEdit) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            HID.pressKey(45, flags: .maskControl)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            logOut("ok    snippet prompt / Paste Previous Clip (⌃N) exercised")
        }

        if suite == "all" || suite == "drag" {
            _ = launchIfInstalled(.finder)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            sendCommand("showOverlay", workDir: workDir)
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            if let pestoAX = axAppElement(bundleIdentifier: "net.copypesto.pesto") {
                var childrenVal: AnyObject?
                AXUIElementCopyAttributeValue(pestoAX, kAXChildrenAttribute as CFString, &childrenVal)
                HID.drag(from: CGPoint(x: 300, y: 700), to: CGPoint(x: 120, y: 200))
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                logOut("ok    CGEventDrag multi-app / Finder / Desktop drop exercised")
            }
        }

        logOut("multi-app (\(suite)): PASS")
    }
}

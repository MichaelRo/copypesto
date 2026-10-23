// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `scripts/clean-test-defaults.sh` matched none of the UUID-named files (its UUID pattern used basic-regex braces
/// inside
/// `grep -E`), so about 4,500 of them survived the first cleanup. It runs against a fake HOME here, in dry-run mode
/// only.
@Suite("clean-test-defaults script")
struct CleanTestDefaultsScriptTests {
    private func dryRun(files: [String]) throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-home-\(UUID().uuidString)")
        let prefs = home.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        for name in files {
            FileManager.default.createFile(
                atPath: prefs.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/clean-test-defaults.sh").path, "--dry-run"]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test("it finds the UUID-named test files and the fixed-name ones, and not the real settings")
    func matchesOnlyThrowawayDomains() throws {
        let uuid = "FF8B54DE-9530-4A69-A2E3-87E6840CF327"
        let output = try dryRun(files: [
            "rules-test-\(uuid).plist", "nsfw-mode-\(uuid.lowercased()).plist", "test-\(uuid).plist",
            "io.pesto.uitest.tests-session-a.plist", "pesto-test-abc.plist",
            "net.copypesto.pesto.plist", "io.pesto.app.plist", "com.apple.finder.plist", "test-notes.plist"
        ])

        #expect(output.contains("5 leftover test preference files"), "\(output)")
    }
}

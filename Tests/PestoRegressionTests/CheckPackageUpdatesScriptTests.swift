// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("check-package-updates.sh")
struct CheckPackageUpdatesScriptTests {
    private static let packagesYAML = """
    name: Pesto
    packages:
      Sparkle:
        url: https://github.com/sparkle-project/Sparkle
        # 2.9.1, pinned by commit because a tag can move
        revision: 066e75a8b3e99962685d6a90cdd5293ebffd9261
    targets:
      Pesto:
        type: application
    """

    private static func advisories(range: String) -> String {
        """
        [{"ghsa_id": "GHSA-test", "summary": "Test flaw", "vulnerabilities": [
          {"package": {"ecosystem": "swift", "name": "github.com/sparkle-project/Sparkle"},
           "first_patched_version": "2.9.2", "vulnerable_version_range": "\(range)"}]}]
        """
    }

    private func run(latest: String, range: String) throws -> (code: Int32, output: String) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-packages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let spec = folder.appendingPathComponent("Pesto.yml")
        try Self.packagesYAML.write(to: spec, atomically: true, encoding: .utf8)
        try "{\"tag_name\": \"\(latest)\"}".write(
            to: folder.appendingPathComponent("sparkle-project__Sparkle.release.json"), atomically: true, encoding: .utf8
        )
        try Self.advisories(range: range).write(
            to: folder.appendingPathComponent("sparkle-project__Sparkle.advisories.json"),
            atomically: true, encoding: .utf8
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            SourceTree.repositoryRoot.appendingPathComponent("scripts/check-package-updates.sh").path, spec.path
        ]
        process.environment = ProcessInfo.processInfo.environment
            .merging(["PESTO_PACKAGES_FIXTURE": folder.path]) { $1 }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    @Test("a pin behind the latest release is flagged loudly and the script still exits 0")
    func whenThePinIsBehind_thenItIsFlaggedAndExitsZero() throws {
        let result = try run(latest: "2.10.1", range: "> 5.0")
        #expect(result.code == 0)
        #expect(result.output.contains("BEHIND"))
        #expect(result.output.contains("!!! check-packages: sparkle-project/Sparkle is behind"))
    }

    @Test("an advisory whose range includes the pinned version is flagged, one that does not is not")
    func whenTheRangeIncludesThePin_thenItIsFlagged() throws {
        let hit = try run(latest: "2.9.1", range: ">= 2.2.0, <= 2.9.1")
        #expect(hit.output.contains("VULNERABLE: GHSA-test"))
        let miss = try run(latest: "2.9.1", range: "< 2.9.1")
        #expect(!miss.output.contains("VULNERABLE"))
        #expect(miss.output.contains("every pin is the latest release"))
    }
}

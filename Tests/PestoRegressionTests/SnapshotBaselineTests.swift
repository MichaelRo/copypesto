// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// The card pictures are only comparable on the macOS version that drew them (audit P-44, `docs/testing.md`, "Card
/// snapshots"): the gate runs them on a matching Mac and says so when it skips them.
@Suite("Snapshot baselines and the gate")
struct SnapshotBaselineTests {
    private func read(_ relative: String) throws -> String {
        try String(contentsOf: SourceTree.repositoryRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    private func check(hostMajor: String, ci: String = "") throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [SourceTree.repositoryRoot.appendingPathComponent("scripts/snapshot-os.sh").path]
        process.environment = ProcessInfo.processInfo.environment
            .merging(["PESTO_SNAPSHOT_HOST_MAJOR": hostMajor, "CI": ci, "PESTO_CI": ci]) { $1 }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    @Test("the baselines record the macOS version that drew them, as one whole number")
    func baselineVersionIsRecorded() throws {
        let recorded = try read("Tests/PestoSnapshotTests/baseline-macos")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(Int(recorded) != nil, "baseline-macos holds \(recorded)")
        #expect((Int(recorded) ?? 0) >= 26)
    }

    @Test("a matching Mac runs the snapshots")
    func matchingMac_runs() throws {
        let recorded = try read("Tests/PestoSnapshotTests/baseline-macos")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try check(hostMajor: recorded)
        #expect(result.code == 0, "\(result.output)")
        #expect(result.output.contains("match"))
    }

    @Test("another macOS version skips them and says which versions differ")
    func otherMac_skipsAndSays() throws {
        let recorded = try read("Tests/PestoSnapshotTests/baseline-macos")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try check(hostMajor: "99")
        #expect(result.code == 1)
        #expect(result.output.contains("snapshots skipped: baselines are macOS \(recorded), this Mac is macOS 99"))
    }

    @Test("a hosted runner skips them even on a matching macOS, because its virtual display draws them differently")
    func hostedRunner_skipsAndSays() throws {
        let recorded = try read("Tests/PestoSnapshotTests/baseline-macos")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try check(hostMajor: recorded, ci: "1")
        #expect(result.code == 1)
        #expect(result.output.contains("snapshots skipped: a hosted runner draws them differently"))
    }

    @Test("verify.sh and make test-snapshots both ask the script, and verify.sh judges the snapshots it ran")
    func toolingUsesTheScript() throws {
        let verify = try read("scripts/verify.sh")
        #expect(verify.contains("scripts/snapshot-os.sh"))
        #expect(verify.contains("--snapshots"))
        #expect(try read("Makefile").contains("scripts/snapshot-os.sh"))
    }
}

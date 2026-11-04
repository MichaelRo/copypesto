// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `xctrace record` hung the second pass of `make bench-scroll` with nothing to stop it. `scripts/run-with-deadline.sh`
/// runs a command and gives up on it after a number of seconds, so a stuck trace fails the pass instead of the run.
@Suite("run-with-deadline.sh")
struct RunWithDeadlineScriptTests {
    private struct Result {
        let code: Int32
        let seconds: Double
        let output: String
    }

    private func run(_ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [SourceTree.repositoryRoot.appendingPathComponent("scripts/run-with-deadline.sh").path]
            + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let start = Date()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            code: process.terminationStatus, seconds: Date().timeIntervalSince(start),
            output: String(bytes: data, encoding: .utf8) ?? ""
        )
    }

    @Test("a command that finishes in time keeps its own exit code and output")
    func whenTheCommandFinishes_thenItsStatusAndOutputPass() throws {
        let ok = try run(["30", "/bin/echo", "traced"])
        #expect(ok.code == 0)
        #expect(ok.output.contains("traced"))
        #expect(ok.seconds < 10)
        let failed = try run(["30", "/bin/sh", "-c", "exit 3"])
        #expect(failed.code == 3)
    }

    @Test("a command that outlives the deadline is stopped and the script exits 124")
    func whenTheCommandHangs_thenItIsKilledAt124() throws {
        let result = try run(["1", "/bin/sleep", "60"])
        #expect(result.code == 124)
        #expect(result.seconds < 15)
        #expect(result.output.contains("gave up"))
    }

    @Test("the children of a hung command are stopped with it")
    func whenTheCommandSpawnsChildren_thenTheyAreStopped() throws {
        let marker = "pesto-deadline-\(UUID().uuidString)"
        let result = try run(["1", "/bin/sh", "-c", "/bin/sleep 61 & /bin/sleep 62 # \(marker)"])
        #expect(result.code == 124)
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        check.arguments = ["-f", "sleep 61"]
        let found = Pipe()
        check.standardOutput = found
        try check.run()
        check.waitUntilExit()
        #expect(check.terminationStatus != 0)
    }
}

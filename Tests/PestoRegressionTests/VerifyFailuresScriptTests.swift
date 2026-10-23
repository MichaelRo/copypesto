// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// A failed gate run used to leave a 900 KB log to read. `scripts/verify_failures.py` turns the result summary into one
/// line per failing test, and into the `-only-testing` arguments that re-run just those.
@Suite("verify.sh failures")
struct VerifyFailuresScriptTests {
    private func run(_ summary: [String: Any], args: [String] = []) throws -> (code: Int32, output: String) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("failures-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: summary).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            SourceTree.repositoryRoot.appendingPathComponent("scripts/verify_failures.py").path,
            file.path
        ] + args
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    private let failure: [String: Any] = [
        "failureText": "XCTAssertFalse failed - an AI answer would repeat what is hidden",
        "targetName": "PestoUITests",
        "testIdentifierString": "SensitiveCardTests/test_blurredCard_offersShowButNotQuickLookOrAIActions()",
        "testName": "test_blurredCard_offersShowButNotQuickLookOrAIActions()"
    ]
    private let runnerError: [String: Any] = [
        "failureText": "The test runner failed to initialize for UI testing. (Underlying Error: Timed out.)",
        "targetName": "PestoUITests",
        "testIdentifierString": "PestoUITests-Runner (7395) encountered an error",
        "testName": "PestoUITests-Runner (7395) encountered an error"
    ]

    @Test("a run with no failures prints nothing")
    func whenNothingFailed_thenNoOutput() throws {
        let result = try run(["failedTests": 0, "testFailures": []])
        #expect(result.code == 0)
        #expect(result.output.isEmpty)
    }

    @Test("each failure is one line with the test, the target and the message")
    func whenATestFailed_thenOneLineNamesIt() throws {
        let result = try run(["failedTests": 1, "testFailures": [failure]])
        let lines = result.output.split(separator: "\n")
        #expect(lines.count == 1)
        #expect(lines[0]
            .hasPrefix("PestoUITests/SensitiveCardTests/test_blurredCard_offersShowButNotQuickLookOrAIActions: "))
        #expect(lines[0].contains("an AI answer would repeat what is hidden"))
    }

    @Test("a long failure message is cut to one readable line")
    func whenTheMessageIsLong_thenItIsCut() throws {
        var long = failure
        long["failureText"] = String(repeating: "x", count: 2000) + "\nsecond line"
        let result = try run(["failedTests": 1, "testFailures": [long]])
        #expect(result.output.split(separator: "\n").count == 1)
        #expect(result.output.count < 400)
    }

    @Test("--only-testing prints the arguments that re-run just the failed tests")
    func whenOnlyTestingRequested_thenArgumentsNameTheFailedTests() throws {
        let result = try run(["failedTests": 1, "testFailures": [failure]], args: ["--only-testing"])
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            == "-only-testing:PestoUITests/SensitiveCardTests/test_blurredCard_offersShowButNotQuickLookOrAIActions")
    }

    @Test("a failure with no test of its own re-runs its whole target")
    func whenARunnerFailedToStart_thenTheWholeTargetIsRerun() throws {
        let result = try run(["failedTests": 2, "testFailures": [failure, runnerError]], args: ["--only-testing"])
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "-only-testing:PestoUITests")
    }
}

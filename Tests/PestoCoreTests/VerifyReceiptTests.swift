// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Release verification receipt check")
struct VerifyReceiptTests {
    private struct TempRepo {
        let dir: URL
        let tree: String
        let commit: String
    }

    private static var scriptURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/check-verify-receipt.sh")
    }

    private static var reconcileScriptURL: URL {
        scriptURL.deletingLastPathComponent().appendingPathComponent("verify_reconcile.py")
    }

    private static var scopeScriptURL: URL {
        scriptURL.deletingLastPathComponent().appendingPathComponent("verify_scope.py")
    }

    private func makeTempGitRepo() throws -> TempRepo {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-verify-receipt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try run("/usr/bin/git", ["init", "-q"], in: dir)
        _ = try run("/usr/bin/git", ["config", "user.email", "test@copypesto.net"], in: dir)
        _ = try run("/usr/bin/git", ["config", "user.name", "Pesto Test"], in: dir)
        try Data("hello\n".utf8).write(to: dir.appendingPathComponent("README.md"))
        _ = try run("/usr/bin/git", ["add", "README.md"], in: dir)
        _ = try run("/usr/bin/git", ["commit", "-q", "-m", "initial"], in: dir)
        let tree = try run("/usr/bin/git", ["rev-parse", "HEAD^{tree}"], in: dir).output.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let commit = try run("/usr/bin/git", ["rev-parse", "HEAD"], in: dir).output.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return TempRepo(dir: dir, tree: tree, commit: commit)
    }

    private func writeReceipt(
        in dir: URL,
        tree: String,
        commit: String,
        dirty: Bool = false,
        fullGate: Bool = true,
        result: String = "PASS"
    ) throws
    -> URL {
        let buildDir = dir.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let receipt = buildDir.appendingPathComponent("verify-receipt.json")
        let payload: [String: Any] = [
            "tree": tree,
            "commit": commit,
            "dirty": dirty,
            "full_gate": fullGate,
            "result": result,
            "run": "20261102-025000",
            "timestamp": "2026-11-02T00:50:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: receipt)
        return receipt
    }

    private func run(
        _ executable: String,
        _ args: [String],
        in dir: URL,
        env: [String: String] = [:]
    ) throws
    -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = dir
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env {
            environment[key] = value
        }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    @Test("a clean repo with a matching full-gate PASS receipt succeeds, including after a commit with the same tree")
    func whenReceiptMatchesCleanTree_thenSucceedsEvenOnNewCommitWithSameTree() throws {
        let repo = try makeTempGitRepo()
        defer { try? FileManager.default.removeItem(at: repo.dir) }
        try Data(".build/\n".utf8).write(to: repo.dir.appendingPathComponent(".gitignore"))
        _ = try run("/usr/bin/git", ["add", ".gitignore"], in: repo.dir)
        _ = try run("/usr/bin/git", ["commit", "-q", "-m", "ignore build"], in: repo.dir)
        let tree = try run("/usr/bin/git", ["rev-parse", "HEAD^{tree}"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = try run("/usr/bin/git", ["rev-parse", "HEAD"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let receipt = try writeReceipt(in: repo.dir, tree: tree, commit: commit)

        let first = try run(Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", receipt.path], in: repo.dir)
        #expect(first.status == 0, "\(first.output)")
        #expect(first.output.contains("Release verify receipt valid"))

        // Simulate squash-merging or rewording a commit with the exact same tree SHA.
        _ = try run("/usr/bin/git", ["commit", "--allow-empty", "-q", "-m", "squash merge"], in: repo.dir)
        let second = try run(Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", receipt.path], in: repo.dir)
        #expect(second.status == 0, "\(second.output)")
    }

    @Test("a missing receipt, a --no-ui/--fast receipt, a mismatched tree, or a dirty working tree is rejected")
    func whenReceiptInvalidOrTreeDirty_thenRejectedUnlessOverridden() throws {
        let repo = try makeTempGitRepo()
        defer { try? FileManager.default.removeItem(at: repo.dir) }
        try Data(".build/\n".utf8).write(to: repo.dir.appendingPathComponent(".gitignore"))
        _ = try run("/usr/bin/git", ["add", ".gitignore"], in: repo.dir)
        _ = try run("/usr/bin/git", ["commit", "-q", "-m", "ignore build"], in: repo.dir)
        let tree = try run("/usr/bin/git", ["rev-parse", "HEAD^{tree}"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = try run("/usr/bin/git", ["rev-parse", "HEAD"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Missing receipt
        let missing = try run(Self.scriptURL.path, ["--repo", repo.dir.path], in: repo.dir)
        #expect(missing.status != 0)
        #expect(missing.output.contains("no full-gate verification receipt found"))

        // 2. --fast / --no-ui receipt (full_gate: false)
        let fastReceipt = try writeReceipt(in: repo.dir, tree: tree, commit: commit, fullGate: false)
        let fast = try run(Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", fastReceipt.path], in: repo.dir)
        #expect(fast.status != 0)
        #expect(fast.output.contains("gate ran with --fast or --no-ui"))

        // 3. Mismatched tree
        let staleReceipt = try writeReceipt(
            in: repo.dir,
            tree: "0000000000000000000000000000000000000000",
            commit: commit
        )
        let stale = try run(
            Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", staleReceipt.path], in: repo.dir
        )
        #expect(stale.status != 0)
        #expect(stale.output.contains("does not match HEAD^{tree}"))

        // 4. Valid receipt, but working tree becomes dirty afterwards
        let validReceipt = try writeReceipt(in: repo.dir, tree: tree, commit: commit)
        try Data("uncommitted edit\n".utf8).write(to: repo.dir.appendingPathComponent("README.md"))
        let dirty = try run(
            Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", validReceipt.path], in: repo.dir
        )
        #expect(dirty.status != 0)
        #expect(dirty.output.contains("working tree has uncommitted changes"))

        // 5. Explicit override env var succeeds with a warning
        let overridden = try run(
            Self.scriptURL.path,
            ["--repo", repo.dir.path, "--receipt", validReceipt.path],
            in: repo.dir,
            env: ["PESTO_SKIP_VERIFY_RECEIPT": "1"]
        )
        #expect(overridden.status == 0)
        #expect(overridden.output.contains("skipping full-gate verification receipt check"))
    }

    @Test("non-code commits after receipt are allowed, while code/build commits or uncommitted changes fail")
    func whenNonCodeOrCodeChangesAfterReceipt_thenCheckedAppropriately() throws {
        let repo = try makeTempGitRepo()
        defer { try? FileManager.default.removeItem(at: repo.dir) }
        try Data(".build/\n".utf8).write(to: repo.dir.appendingPathComponent(".gitignore"))
        _ = try run("/usr/bin/git", ["add", ".gitignore"], in: repo.dir)
        _ = try run("/usr/bin/git", ["commit", "-q", "-m", "ignore build"], in: repo.dir)
        let tree = try run("/usr/bin/git", ["rev-parse", "HEAD^{tree}"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = try run("/usr/bin/git", ["rev-parse", "HEAD"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let receipt = try writeReceipt(in: repo.dir, tree: tree, commit: commit)

        // 1. Untracked scratch files do not dirty the check
        try Data("scratch notes\n".utf8).write(to: repo.dir.appendingPathComponent("scratch.md"))
        let untracked = try run(Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", receipt.path], in: repo.dir)
        #expect(untracked.status == 0, "\(untracked.output)")

        // 2. Non-code commit (e.g. docs/README) after verify is accepted
        try Data("updated docs\n".utf8).write(to: repo.dir.appendingPathComponent("README.md"))
        _ = try run("/usr/bin/git", ["add", "README.md"], in: repo.dir)
        _ = try run("/usr/bin/git", ["commit", "-q", "-m", "docs: update readme"], in: repo.dir)
        let nonCode = try run(Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", receipt.path], in: repo.dir)
        #expect(nonCode.status == 0, "\(nonCode.output)")

        // 3. Code commit after verify is rejected
        let sourcesDir = repo.dir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try Data("let x = 1\n".utf8).write(to: sourcesDir.appendingPathComponent("Test.swift"))
        _ = try run("/usr/bin/git", ["add", "Sources/Test.swift"], in: repo.dir)
        _ = try run("/usr/bin/git", ["commit", "-q", "-m", "feat: add file"], in: repo.dir)
        let codeChange = try run(
            Self.scriptURL.path,
            ["--repo", repo.dir.path, "--receipt", receipt.path],
            in: repo.dir
        )
        #expect(codeChange.status != 0)
        #expect(codeChange.output.contains("code or build configuration changed"))
    }

    @Test("a reconciled full-gate receipt is accepted with provenance, while a scoped receipt is rejected")
    func whenReconciledOrScopedReceiptChecked_thenValidatedAppropriately() throws {
        let repo = try makeTempGitRepo()
        defer { try? FileManager.default.removeItem(at: repo.dir) }
        try Data(".build/\n".utf8).write(to: repo.dir.appendingPathComponent(".gitignore"))
        _ = try run("/usr/bin/git", ["add", ".gitignore"], in: repo.dir)
        _ = try run("/usr/bin/git", ["commit", "-q", "-m", "ignore build"], in: repo.dir)
        let tree = try run("/usr/bin/git", ["rev-parse", "HEAD^{tree}"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = try run("/usr/bin/git", ["rev-parse", "HEAD"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildDir = repo.dir.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let receipt = buildDir.appendingPathComponent("verify-receipt.json")

        let reconciledPayload: [String: Any] = [
            "tree": tree, "commit": commit, "dirty": false, "full_gate": true,
            "reconciled": true, "reconciled_from": "20261108-010000", "rerun_stamp": "20261108-011500",
            "result": "PASS", "run": "20261108-010000", "timestamp": "2026-11-08T01:15:00Z"
        ]
        try JSONSerialization.data(withJSONObject: reconciledPayload).write(to: receipt)
        let validReconciled = try run(
            Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", receipt.path], in: repo.dir
        )
        #expect(validReconciled.status == 0, "\(validReconciled.output)")
        #expect(validReconciled.output.contains("Release verify receipt valid"))

        var incompletePayload = reconciledPayload
        incompletePayload.removeValue(forKey: "rerun_stamp")
        try JSONSerialization.data(withJSONObject: incompletePayload).write(to: receipt)
        let incomplete = try run(
            Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", receipt.path], in: repo.dir
        )
        #expect(incomplete.status != 0)
        #expect(incomplete.output.contains("reconciled receipt is missing"))

        let scopedPayload: [String: Any] = [
            "tree": tree, "commit": commit, "dirty": false, "full_gate": false, "scoped": true,
            "result": "PASS", "run": "20261108-012000", "timestamp": "2026-11-08T01:20:00Z"
        ]
        try JSONSerialization.data(withJSONObject: scopedPayload).write(to: receipt)
        let scoped = try run(
            Self.scriptURL.path, ["--repo", repo.dir.path, "--receipt", receipt.path], in: repo.dir
        )
        #expect(scoped.status != 0)
        #expect(scoped.output.contains("--scoped"))
    }

    private func makeTestNodes(hostedPassed: Int, uiPassed: Int, failedID: String?) -> [String: Any] {
        let hostedCases: [[String: Any]] = (0..<hostedPassed).map {
            ["nodeType": "Test Case", "name": "h\($0)", "nodeIdentifier": "Suite/h\($0)", "result": "Passed"]
        }
        var uiCases: [[String: Any]] = (0..<uiPassed).map {
            ["nodeType": "Test Case", "name": "u\($0)", "nodeIdentifier": "UISuite/u\($0)", "result": "Passed"]
        }
        if let failedID {
            uiCases.append(["nodeType": "Test Case", "name": failedID, "nodeIdentifier": failedID, "result": "Failed"])
        }
        return [
            "testNodes": [
                ["nodeType": "Unit test bundle", "name": "PestoTests", "children": hostedCases],
                ["nodeType": "UI test bundle", "name": "PestoUITests", "children": uiCases]
            ]
        ]
    }

    @Test("verify_reconcile.py writes a valid receipt when all failed hosted/UI tests pass on rerun")
    func whenVerifyReconcileRuns_thenStampsReceiptOnlyWhenSafe() throws {
        let repo = try makeTempGitRepo()
        defer { try? FileManager.default.removeItem(at: repo.dir) }
        try Data(".build/\n".utf8).write(to: repo.dir.appendingPathComponent(".gitignore"))
        _ = try run("/usr/bin/git", ["add", ".gitignore"], in: repo.dir)
        _ = try run("/usr/bin/git", ["commit", "-q", "-m", "ignore build"], in: repo.dir)
        let tree = try run("/usr/bin/git", ["rev-parse", "HEAD^{tree}"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = try run("/usr/bin/git", ["rev-parse", "HEAD"], in: repo.dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let runID = "20261108-020000"
        let stamp = "20261108-021000"
        let runDir = repo.dir.appendingPathComponent(".build/verify/\(runID)", isDirectory: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        let flakyID = "SensitiveCardTests/test_blurredCard()"
        try JSONSerialization.data(withJSONObject: [
            "passedTests": 410, "failedTests": 1,
            "testFailures": [["targetName": "PestoUITests", "testIdentifierString": flakyID, "testName": flakyID]]
        ]).write(to: runDir.appendingPathComponent("tests-summary.json"))
        try JSONSerialization.data(withJSONObject: makeTestNodes(hostedPassed: 280, uiPassed: 130, failedID: flakyID))
            .write(to: runDir.appendingPathComponent("tests-tree.json"))
        try JSONSerialization.data(withJSONObject: ["passedTests": 1, "failedTests": 0, "testFailures": []])
            .write(to: runDir.appendingPathComponent("rerun-\(stamp)-summary.json"))
        try JSONSerialization.data(withJSONObject: [
            "testNodes": [[
                "nodeType": "UI test bundle", "name": "PestoUITests",
                "children": [["nodeType": "Test Case", "name": flakyID, "nodeIdentifier": flakyID, "result": "Passed"]]
            ]]
        ]).write(to: runDir.appendingPathComponent("rerun-\(stamp)-tree.json"))

        func meta(steps: [[String: String]]) -> [String: Any] {
            [
                "run": runID, "tree": tree, "commit": commit, "dirty": false, "full_gate": true,
                "scoped": false, "runs_snapshots": false, "skip_ui": false, "steps": steps
            ]
        }
        try JSONSerialization.data(withJSONObject: meta(steps: [
            ["name": "lint", "status": "FAIL"], ["name": "hosted + UI tests", "status": "FAIL"]
        ])).write(to: runDir.appendingPathComponent("run-meta.json"))
        let refused = try run(
            "/usr/bin/python3",
            [Self.reconcileScriptURL.path, "--repo", repo.dir.path, "--run-dir", runDir.path, "--stamp", stamp],
            in: repo.dir
        )
        #expect(refused.status != 0)
        #expect(refused.output.contains("non-test step failed"))

        try JSONSerialization.data(withJSONObject: meta(steps: [
            ["name": "lint", "status": "PASS"], ["name": "core tests", "status": "PASS"],
            ["name": "hosted + UI tests", "status": "FAIL"]
        ])).write(to: runDir.appendingPathComponent("run-meta.json"))
        let reconciled = try run(
            "/usr/bin/python3",
            [Self.reconcileScriptURL.path, "--repo", repo.dir.path, "--run-dir", runDir.path, "--stamp", stamp],
            in: repo.dir
        )
        #expect(reconciled.status == 0, "\(reconciled.output)")
        let check = try run(Self.scriptURL.path, ["--repo", repo.dir.path], in: repo.dir)
        #expect(check.status == 0, "\(check.output)")
    }

    @Test("verify_scope.py maps changed files to targeted test suites")
    func whenVerifyScopeEvaluatesChangesets_thenScopesTargetsAppropriately() throws {
        // 1. Core-only change runs Core tests and skips UI tests
        let coreOnly = try run(
            "/usr/bin/python3",
            [
                Self.scopeScriptURL.path,
                "--files",
                "Sources/Core/Storage/HistoryIndex.swift",
                "Tests/PestoCoreTests/HistoryIndexTests.swift"
            ],
            in: FileManager.default.temporaryDirectory
        )
        #expect(coreOnly.status == 0, "\(coreOnly.output)")
        let corePlan = try #require(
            JSONSerialization.jsonObject(with: Data(coreOnly.output.utf8)) as? [String: Any]
        )
        #expect(corePlan["run_core"] as? Bool == true)
        #expect(corePlan["run_ui"] as? Bool == false)
        #expect((corePlan["core_filter"] as? String)?.contains("HistoryIndexTests") == true)

        // 2. Grid feature change runs hosted, snapshot, and targeted UI suites
        let gridChange = try run(
            "/usr/bin/python3",
            [Self.scopeScriptURL.path, "--files", "Sources/Features/Grid/ClipboardCard.swift"],
            in: FileManager.default.temporaryDirectory
        )
        #expect(gridChange.status == 0, "\(gridChange.output)")
        let gridPlan = try #require(
            JSONSerialization.jsonObject(with: Data(gridChange.output.utf8)) as? [String: Any]
        )
        #expect(gridPlan["run_hosted"] as? Bool == true)
        #expect(gridPlan["run_ui"] as? Bool == true)
        let onlyTesting = gridPlan["only_testing"] as? [String] ?? []
        #expect(onlyTesting.contains("PestoUITests/OverlayFlowTests"))
        #expect(onlyTesting.contains("PestoUITests/KeyboardNavigationTests"))
    }
}

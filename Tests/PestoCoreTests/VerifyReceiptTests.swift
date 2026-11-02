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
}

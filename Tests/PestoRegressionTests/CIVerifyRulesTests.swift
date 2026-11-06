// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// The macOS `verify` job costs about twenty minutes a pull request. It must not run for a pull request stacked on
/// another branch, and not again for content that already passed (a rebase that changed no file, a re-run).
@Suite("CI verify skips what it need not repeat")
struct CIVerifyRulesTests {
    private func workflow() throws -> String {
        try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8
        )
    }

    private func verifyJob(_ text: String) throws -> String {
        let start = try #require(text.range(of: "\n  verify:\n"), "no verify job")
        return String(text[start.lowerBound...])
    }

    @Test("verify runs only for a pull request whose base is the default branch")
    func whenStacked_thenVerifyDoesNotRun() throws {
        let job = try verifyJob(workflow())
        #expect(job.contains("github.base_ref == github.event.repository.default_branch"))
        #expect(job.contains("github.event_name != 'push'"))
        #expect(
            job.contains("github.event_name == 'workflow_dispatch' ||"),
            "a manual run has no base_ref and must still run"
        )
    }

    @Test("a green run leaves a marker keyed by the pull request's tree, and a run that finds it skips the work")
    func whenTheTreeAlreadyPassed_thenEveryStepIsSkipped() throws {
        let text = try workflow()
        let job = try verifyJob(text)
        let key = "verified-${{ needs.detect-changes.outputs.tree }}"
        #expect(job.components(separatedBy: key).count - 1 == 2, "the marker is restored and saved under one key")
        #expect(job.contains("actions/cache/restore@"))
        #expect(job.contains("actions/cache/save@"))
        #expect(text.contains("git ls-tree HEAD -- \"${code_paths[@]}\""), "the key is the merge's code paths")
        #expect(
            !text.contains("^{tree}"),
            "the key is not the pull request's head tree: a re-run after main moved is no pass"
        )
        for path in ["Sources", "Tests", "Pesto.resolved", "scripts", "Makefile", ".github/workflows"] {
            #expect(text.contains(path), "\(path) is part of what verify judges")
        }
        let verifyStep = try #require(job.range(of: "scripts/verify.sh --no-ui"))
        let before = String(job[..<verifyStep.lowerBound])
        let step = try #require(before.components(separatedBy: "      - ").last)
        #expect(step.contains("steps.seen.outputs.cache-hit != 'true'"), "the gate itself is skipped on a hit")
        let save = try #require(job.range(of: "actions/cache/save@"))
        let saveStep = String(job[..<save.lowerBound]).components(separatedBy: "      - ").last ?? ""
        #expect(saveStep.contains("success()"), "only a passing run saves the marker")
    }
}

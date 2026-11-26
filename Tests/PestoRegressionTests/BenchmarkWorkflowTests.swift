// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `.github/workflows/benchmarks.yml` runs automated CPU, memory, and latency checks on pushes to `main`.
/// Keep its permissions minimal, third-party actions pinned to commit SHAs, and `scripts/bench-thresholds.json` valid.
@Suite("Benchmark workflow and thresholds")
struct BenchmarkWorkflowTests {
    private let root = SourceTree.repositoryRoot

    @Test("benchmarks.yml pins actions to SHAs, uses read-only permissions, and runs on main pushes")
    func whenReadingWorkflow_thenSecurityAndTriggerInvariantsHold() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/benchmarks.yml"),
            encoding: .utf8
        )
        #expect(text.contains("branches: [main]"))
        #expect(text.contains("workflow_dispatch:"))
        #expect(text.contains("contents: read"))
        #expect(!text.contains("contents: write"))
        #expect(text.contains("persist-credentials: false"))
        #expect(text.contains("PESTO_BENCH_SKIP_PROFILE: \"1\""))
        #expect(text.contains("scripts/bench-ci.sh"))

        for line in text.split(separator: "\n") {
            let raw = String(line)
            guard raw.contains("uses:") else { continue }
            let match = raw.firstMatch(of: /uses:\s*[^@\s]+@([0-9a-f]{40})\b/)
            #expect(match != nil, "action is not pinned to a 40-char commit SHA: \(raw)")
        }
    }

    @Test("bench-thresholds.json is valid JSON with local and CI limits for every metric")
    func whenReadingThresholds_thenEveryMetricHasValidLimits() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/bench-thresholds.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metrics = try #require(object["metrics"] as? [String: Any])
        #expect(metrics.count >= 12)
        for (key, value) in metrics {
            let entry = try #require(value as? [String: Any], "\(key) must be an object")
            let localMax = try #require(entry["local_max"] as? Double, "\(key) missing local_max")
            let ciMax = try #require(entry["ci_max"] as? Double, "\(key) missing ci_max")
            #expect(localMax > 0, "\(key) local_max must be positive")
            #expect(ciMax >= localMax, "\(key) ci_max must be >= local_max")
            _ = try #require(entry["unit"] as? String, "\(key) missing unit")
            _ = try #require(entry["label"] as? String, "\(key) missing label")
        }
    }

    @Test("bench_report.py and review_grid.py unit test suites pass")
    func whenRunningPythonToolingTests_thenAllPass() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = root
        process.arguments = ["python3", "-m", "unittest", "scripts/test_bench_report.py", "scripts/test_review_grid.py"]
        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "python unittest failed: \(stderr)")
    }
}

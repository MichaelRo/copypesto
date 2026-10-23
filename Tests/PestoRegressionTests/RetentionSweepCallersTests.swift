// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Retention sweep")
struct RetentionSweepCallersTests {
    private func appDelegate() throws -> String {
        let file = SourceTree.sources.appendingPathComponent("App/AppDelegate.swift")
        return try String(contentsOf: file, encoding: .utf8)
    }

    @Test("showing the shelf never starts a retention sweep (P-01: it cost 78 ms of a 100 ms budget)")
    func showOverlayDoesNotSweep() throws {
        let source = try appDelegate()
        let start = try #require(source.range(of: "func showOverlay("))
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    func ")?.lowerBound ?? rest.endIndex
        let body = rest[..<end]

        #expect(!body.contains("sweepRetention"), "a sweep belongs to launch, the timer and a policy change")
        #expect(!body.contains("retentionSnapshot"))
    }

    @Test("a sweep starts only at launch, on the timer and when the policy changes")
    func sweepHasThreeCallers() throws {
        var callers: [String] = []
        for file in try SourceTree.files(in: "", minimum: 100) {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated()
                where line.contains("sweepRetention(") && !line.contains("static func sweepRetention")
            {
                callers.append("\(file.lastPathComponent):\(number + 1)")
            }
        }

        #expect(callers.count == 3, "expected launch, timer and applyRetentionChange, found \(callers)")
    }
}

// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Force unwraps")
struct ForceUnwrapScanTests {
    @Test("production code has no lint-disabled force unwrap (AGENTS.md bans them, R-09)")
    func noDisabledForceUnwrap() throws {
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated()
                where line.contains("swiftlint:disable") && line.contains("force_unwrapping")
            {
                offenders.append("\(SourceTree.relativePath(file)):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty, "use if let or guard instead: \(offenders.joined(separator: ", "))")
    }
}

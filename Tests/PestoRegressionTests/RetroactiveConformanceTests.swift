// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Conformances on Apple types")
struct RetroactiveConformanceTests {
    @Test("no Apple type is declared Sendable by Pesto (a wrapper owns the claim, so Apple's own can arrive safely)")
    func noRetroactiveUncheckedSendable() throws {
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated()
                where line.contains("@retroactive @unchecked Sendable") || line.contains("@retroactive Sendable")
            {
                offenders.append("\(file.lastPathComponent):\(number + 1)")
            }
        }

        #expect(
            offenders.isEmpty,
            "wrap the type, as SystemPasteboard wraps NSPasteboard: \(offenders.joined(separator: ", "))"
        )
    }
}

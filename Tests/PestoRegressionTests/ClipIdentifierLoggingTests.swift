// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Logging")
struct ClipIdentifierLoggingTests {
    @Test("a clip id is never logged with privacy: .public (it is what pesto://paste?id= needs, R-11)")
    func clipIdentifiersAreLoggedPrivately() throws {
        let pattern = try NSRegularExpression(
            pattern: #"\\\(\s*(?:id|ids|itemID|itemIDs|clipID|clipIDs|item\.id|clip\.id)\s*,\s*privacy:\s*\.public"#
        )
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated()
                where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            {
                offenders.append("\(file.lastPathComponent):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty, "use privacy: .private for a clip id: \(offenders.joined(separator: ", "))")
    }
}

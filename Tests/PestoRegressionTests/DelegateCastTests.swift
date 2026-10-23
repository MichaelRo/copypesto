// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("App delegate access")
struct DelegateCastTests {
    @Test(
        "nothing casts NSApp.delegate to AppDelegate (SwiftUI wraps it: the cast is nil and nothing happens)"
    )
    func noDelegateCasts() throws {
        let pattern = try NSRegularExpression(pattern: #"delegate\s+as\?\s+AppDelegate"#)
        var offenders: [String] = []
        let files = try SourceTree.everySwiftFile()
        for file in files {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated()
                where !line.trimmingCharacters(in: .whitespaces).hasPrefix("///")
                && pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            {
                offenders.append("\(file.lastPathComponent):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty, "use ScriptingContext or AppState instead: \(offenders.joined(separator: ", "))")
    }
}

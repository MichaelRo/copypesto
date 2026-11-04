// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// A collection keeps a clip where it was only because every use of a clip moves it to the front through
/// `ClipboardItem.bringToFront(at:)`, which remembers the first copy (ADR 0021). A bare `item.timestamp = …` would
/// move a clip inside its collection again without any test failing, so none may exist outside an initializer.
@Suite("Writers of a clip's timestamp")
struct TimestampWritersTests {
    @Test("no source file assigns a clip's timestamp directly: a use goes through bringToFront")
    func noDirectAssignments() throws {
        let assignment = try NSRegularExpression(pattern: #"[A-Za-z0-9_\)\]]\.timestamp\s*=[^=]"#)
        var scanned = 0
        var offenders: [String] = []
        for (folder, minimum) in [("App", 30), ("Features", 60), ("Shared", 15), ("Core", 200), ("CLI", 1)] {
            for file in try SourceTree.swiftFiles(in: folder, minimum: minimum) {
                scanned += 1
                let text = try String(contentsOf: file, encoding: .utf8)
                for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    let code = String(line)
                    let range = NSRange(code.startIndex..., in: code)
                    if code.contains("self.timestamp") { continue }
                    if assignment.firstMatch(in: code, range: range) != nil {
                        offenders.append("\(file.lastPathComponent):\(number + 1)")
                    }
                }
            }
        }
        #expect(scanned > 100, "the sources were not found")
        #expect(offenders.isEmpty, "use ClipboardItem.bringToFront(at:) so a collection keeps the clip: \(offenders)")
    }

    @Test("the pattern catches an assignment and ignores a comparison and an initializer")
    func patternBehaves() throws {
        let assignment = try NSRegularExpression(pattern: #"[A-Za-z0-9_\)\]]\.timestamp\s*=[^=]"#)
        func matches(_ code: String) -> Bool {
            assignment.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil
        }
        #expect(matches("        item.timestamp = Date()"))
        #expect(matches("similar.timestamp = now"))
        #expect(!matches("if item.timestamp == other.timestamp {"))
        #expect(!matches("let copy = Foo(timestamp: now)"))
    }
}

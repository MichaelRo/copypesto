// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// Sync is only ever your own Macs. "Group" reads as people and sharing, so no sentence a person can read calls
/// what the Macs keep matching a "group" (it is "sync", and "your other Macs"). Code names such as `SyncGroup` and
/// comments are internal and stay.
@Suite("Sync wording")
struct SyncWordingTests {
    private static let banned = try? NSRegularExpression(
        pattern: #"sync(?:ing)? group|\bin the group\b|\bthe group (?:has|changed)\b|\bfinds the group\b"#,
        options: .caseInsensitive
    )
    private static let literal = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)

    @Test("no string a person can read in the app calls sync a group")
    func appStrings() throws {
        var offenders: [String] = []
        for (folder, minimum) in [("Features", 50), ("App", 10), ("Core", 100)] {
            for file in try SourceTree.swiftFiles(in: folder, minimum: minimum) {
                let text = try String(contentsOf: file, encoding: .utf8)
                for (number, line) in text.components(separatedBy: "\n").enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") { continue }
                    let range = NSRange(line.startIndex..., in: line)
                    for match in Self.literal?.matches(in: line, range: range) ?? [] {
                        guard let found = Range(match.range, in: line) else { continue }
                        let spoken = String(line[found])
                        if Self.banned?
                            .firstMatch(in: spoken, range: NSRange(spoken.startIndex..., in: spoken)) != nil
                        {
                            offenders.append("\(file.lastPathComponent):\(number + 1) \(spoken)")
                        }
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders.joined(separator: "; "))")
    }

    @Test("the README and the guide do not call sync a group either")
    func documents() throws {
        let root = SourceTree.repositoryRoot
        var files = [root.appendingPathComponent("README.md"), root.appendingPathComponent("ROADMAP.md")]
        let guide = root.appendingPathComponent("docs/guide")
        files += try FileManager.default.contentsOfDirectory(at: guide, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if Self.banned?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty, "\(offenders.joined(separator: ", "))")
    }
}

// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Settings registry")
struct SettingsRegistryTests {
    @Test(
        "no preference is read or written under a raw key: it goes through Setting, which holds the key and the default"
    )
    func noRawPreferenceKeys() throws {
        let rawKey = try NSRegularExpression(
            pattern: #"@AppStorage\("|\.(?:bool|integer|string|object|double|data|array|set|removeObject)"#
                + #"\([^)\n]*forKey: ""#
        )
        var offenders: [String] = []
        for file in try SourceTree.everySwiftFile() where file.lastPathComponent != "Setting.swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                if rawKey.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    offenders.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }

        #expect(offenders.isEmpty, "use Setting.<key>: \(offenders.joined(separator: ", "))")
    }

    @Test("every key declared in Setting is in Setting.allNames, so the uniqueness check covers it")
    func everyKeyIsListed() throws {
        let file = SourceTree.sources.appendingPathComponent("Core/Runtime/Setting.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let declared = lines.count(where: { $0.contains("public static let ") && $0.contains("= SettingKey(") })
        let listed = try #require(text.components(separatedBy: "allNames: [String] = [").last)
        let names = listed.components(separatedBy: ".name").count - 1

        #expect(declared == names, "\(declared) keys declared, \(names) listed in allNames")
    }
}

// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("License headers")
struct LicenseHeaderTests {
    private static let header = "// SPDX-License-Identifier: MIT"

    @Test("every Swift file starts with the SPDX line (after a #! or swift-tools-version line, which must come first)")
    func everySwiftFileHasTheSPDXLine() throws {
        let root = SourceTree.repositoryRoot
        var files = [root.appendingPathComponent("Package.swift")]
        for (folder, minimum) in [("Sources", 280), ("Tests", 100), ("scripts", 1), ("design", 1)] {
            files += try SourceTree.files(in: folder, minimum: minimum, under: root)
        }
        #expect(files.count > 400)

        let offenders = try files.filter { file in
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            let mustComeFirst = lines.first.map { $0.hasPrefix("#!") || $0.hasPrefix("// swift-tools-version") }
            let expectedIndex = mustComeFirst == true ? 1 : 0
            return lines.count <= expectedIndex || lines[expectedIndex] != Self.header
        }.map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }

        #expect(
            offenders.isEmpty,
            "add \(Self.header) as the first line: \(offenders.sorted().joined(separator: ", "))"
        )
    }

    @Test("every shell and Python script carries the SPDX line after its #! line (V-B4)")
    func everyScriptHasTheSPDXLine() throws {
        let root = SourceTree.repositoryRoot
        let scripts = try SourceTree.files(in: "scripts", extensions: ["sh", "py"], minimum: 20, under: root)
        let offenders = try scripts.filter { file in
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            let index = lines.first?.hasPrefix("#!") == true ? 1 : 0
            return lines.count <= index || lines[index] != "# SPDX-License-Identifier: MIT"
        }.map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }

        #expect(offenders.isEmpty, "add # SPDX-License-Identifier: MIT: \(offenders.sorted().joined(separator: ", "))")
    }
}

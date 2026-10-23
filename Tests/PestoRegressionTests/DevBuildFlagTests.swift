// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `Info.plist` carries `PestoDevelopmentBuild = $(PESTO_DEV_BUILD)`. A variable no configuration defines expands to an
/// empty string, which `BuildKind` reads as a shipped build, so Xcode's Run polled the real update feed.
@Suite("The development build flag")
struct DevBuildFlagTests {
    private static func projectSpec() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Pesto.yml"), encoding: .utf8)
    }

    private static func block(named name: String, in text: String) -> String {
        guard let start = text.range(of: "\n    \(name):\n") else { return "" }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n    [A-Za-z]+:\n|\n[a-z]+:", options: .regularExpression)?.lowerBound ?? rest
            .endIndex
        return String(rest[..<end])
    }

    @Test("every configuration spells the flag: Debug and Profile are development builds, Release is shipped")
    func flagIsDefinedPerConfiguration() throws {
        let spec = try Self.projectSpec()
        #expect(
            spec.contains("PESTO_DEV_BUILD: \"NO\""),
            "the base setting must define the flag, or Xcode expands it to empty"
        )
        #expect(Self.block(named: "Debug", in: spec).contains("PESTO_DEV_BUILD: \"YES\""))
        #expect(Self.block(named: "Profile", in: spec).contains("PESTO_DEV_BUILD: \"YES\""))
        #expect(!Self.block(named: "Release", in: spec).contains("PESTO_DEV_BUILD: \"YES\""))
    }
}

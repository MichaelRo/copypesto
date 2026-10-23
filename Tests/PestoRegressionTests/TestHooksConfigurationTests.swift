// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Only Debug and Profile builds allow the UI-test harness")
struct TestHooksConfigurationTests {
    @Test("Pesto.yml turns test hooks on in no configuration but Debug and Profile")
    func hooksAreOnlyEnabledForDebugAndProfile() throws {
        let url = SourceTree.repositoryRoot.appendingPathComponent("Pesto.yml")
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        let enabled = lines.indices.filter { lines[$0].contains(#"PESTO_ALLOWS_TEST_HOOKS: "YES""#) }
        #expect(enabled.count == 2, "expected the Debug and Profile settings, found \(enabled.count)")

        let base = lines.filter { $0.contains("PESTO_ALLOWS_TEST_HOOKS:") && $0.hasPrefix("    P") }
        #expect(base.contains { $0.contains(#""NO""#) }, "the default must be NO")

        for index in enabled {
            let config = lines[..<index].last { line in
                line.hasPrefix("    ") && !line.hasPrefix("     ") && line.hasSuffix(":")
            }
            let name = config?.trimmingCharacters(in: .whitespaces) ?? ""
            #expect(["Debug:", "Profile:"].contains(name), "test hooks are enabled under '\(name)'")
        }
    }

    @Test("the Info.plist reads the flag from the build setting")
    func infoPlistUsesTheBuildSetting() throws {
        let url = SourceTree.sources.appendingPathComponent("Resources/Info.plist")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("<key>PestoAllowsTestHooks</key>"))
        #expect(text.contains("$(PESTO_ALLOWS_TEST_HOOKS)"))
    }
}

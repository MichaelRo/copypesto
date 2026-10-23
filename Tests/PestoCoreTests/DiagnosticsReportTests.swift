// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("The diagnostics a person can copy into a bug report")
struct DiagnosticsReportTests {
    private let facts = DiagnosticsReport.Facts(
        appVersion: "1.0.0", build: "42", macOS: "Version 15.4 (Build 24E248)", hardware: "Mac15,12",
        architecture: "arm64", isDevelopmentBuild: false,
        switches: [("Accessibility", true), ("History lock", false), ("Link previews", false)],
        keepsClipsForDays: 30
    )

    @Test("it names the app, the Mac and the switches, one fact per line")
    func whenBuilt_thenReadable() {
        let lines = DiagnosticsReport.text(facts).split(separator: "\n").map(String.init)

        #expect(lines.first == "Pesto 1.0.0 (42)")
        #expect(lines.contains("macOS: Version 15.4 (Build 24E248)"))
        #expect(lines.contains("Mac: Mac15,12 (arm64)"))
        #expect(lines.contains("Accessibility: on"))
        #expect(lines.contains("History lock: off"))
        #expect(lines.contains("Keeps clips for (days): 30"))
    }

    @Test("a development build says so, and keeping clips forever is spelled out")
    func whenDevelopmentAndForever_thenSaid() {
        var changed = facts
        changed.isDevelopmentBuild = true
        changed.keepsClipsForDays = 0

        let text = DiagnosticsReport.text(changed)

        #expect(text.contains("Pesto 1.0.0 (42), development build"))
        #expect(text.contains("Keeps clips for (days): forever"))
    }

    @Test("the report holds only the facts it is given: nothing from the history")
    func whenBuilt_thenNoClipContentFieldExists() {
        let mirror = Mirror(reflecting: facts)
        let names = Set(mirror.children.compactMap(\.label))

        #expect(names == [
            "appVersion", "build", "macOS", "hardware", "architecture", "isDevelopmentBuild", "switches",
            "keepsClipsForDays"
        ])
    }
}

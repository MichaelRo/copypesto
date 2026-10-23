// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("AppPaths")
struct AppPathsTests {
    private let applicationSupport = URL(fileURLWithPath: "/Users/someone/Library/Application Support")
    private let temporary = URL(fileURLWithPath: "/var/folders/xx/T")

    private func configuration(mode: LaunchMode, session: String = "default") -> RuntimeConfiguration {
        RuntimeConfiguration(mode: mode, session: session, seed: .basic, accessibility: .trusted)
    }

    @Test("a normal launch keeps its data in Application Support")
    func whenNormal_thenApplicationSupport() {
        let url = AppPaths.supportDirectory(
            for: configuration(mode: .normal),
            applicationSupport: applicationSupport,
            temporary: temporary
        )
        #expect(url.path == "/Users/someone/Library/Application Support/net.copypesto.pesto")
    }

    @Test("a uiTest launch keeps its data in a session-scoped temporary directory")
    func whenUITest_thenTemporarySessionDirectory() {
        let url = AppPaths.supportDirectory(
            for: configuration(mode: .uiTest, session: "run-42"),
            applicationSupport: applicationSupport,
            temporary: temporary
        )
        #expect(url.path == "/var/folders/xx/T/io.pesto.uitest.run-42")
    }

    @Test("an explicit uiTest directory wins over the temporary directory")
    func whenUITestDirectory_thenUsedDirectly() {
        var config = configuration(mode: .uiTest, session: "run-42")
        config.directory = URL(fileURLWithPath: "/tmp/pesto-run-42")
        let url = AppPaths.supportDirectory(for: config, applicationSupport: applicationSupport, temporary: temporary)
        #expect(url.path == "/tmp/pesto-run-42")
    }

    @Test("a hosted test run never touches Application Support")
    func whenHostedTests_thenTemporaryDirectory() {
        let url = AppPaths.supportDirectory(
            for: configuration(mode: .hostedTests),
            applicationSupport: applicationSupport,
            temporary: temporary
        )
        #expect(!url.path.hasPrefix(applicationSupport.path))
    }

    @Test("different sessions get different directories")
    func whenDifferentSessions_thenDifferentDirectories() {
        let first = AppPaths.supportDirectory(
            for: configuration(mode: .uiTest, session: "a"),
            applicationSupport: applicationSupport,
            temporary: temporary
        )
        let second = AppPaths.supportDirectory(
            for: configuration(mode: .uiTest, session: "b"),
            applicationSupport: applicationSupport,
            temporary: temporary
        )
        #expect(first != second)
    }
}

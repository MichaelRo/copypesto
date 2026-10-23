// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("AppDefaults isolation")
struct AppDefaultsTests {
    private func configuration(mode: LaunchMode, session: String) -> RuntimeConfiguration {
        RuntimeConfiguration(
            mode: mode,
            session: session,
            seed: .basic,
            accessibility: .trusted
        )
    }

    @Test("a normal launch uses the user's real defaults")
    func whenNormal_thenStandardDefaults() {
        let store = AppDefaults.makeStore(for: configuration(mode: .normal, session: "default"))
        #expect(store === UserDefaults.standard)
    }

    @Test("a uiTest launch writes to a private suite, never the real defaults")
    func whenUITest_thenWritesDoNotReachStandard() {
        let session = "tests-isolation"
        let store = AppDefaults.makeStore(for: configuration(mode: .uiTest, session: session))
        let key = "pestoIsolationProbe-\(UUID().uuidString)"

        store.set("value", forKey: key)

        #expect(store !== UserDefaults.standard)
        #expect(store.string(forKey: key) == "value")
        #expect(UserDefaults.standard.string(forKey: key) == nil)
    }

    @Test("a hosted test run writes to a private suite, never the real defaults")
    func whenHostedTests_thenWritesDoNotReachStandard() {
        let store = AppDefaults.makeStore(for: configuration(mode: .hostedTests, session: "default"))
        let key = "pestoIsolationProbe-\(UUID().uuidString)"

        store.set("value", forKey: key)

        #expect(store !== UserDefaults.standard)
        #expect(UserDefaults.standard.string(forKey: key) == nil)
    }

    @Test("a uiTest launch starts with the requested preference overrides")
    func whenOverrides_thenAppliedToStore() {
        let session = "tests-overrides"
        var config = configuration(mode: .uiTest, session: session)
        config.defaultOverrides = [
            "hasOnboarded": .bool(true),
            "appearanceMode": .string("dark"),
            "retentionDays": .int(7)
        ]
        let seeded = AppDefaults.makeStore(for: config)

        #expect(seeded.bool(forKey: "hasOnboarded"))
        #expect(seeded.string(forKey: "appearanceMode") == "dark")
        #expect(seeded.integer(forKey: "retentionDays") == 7)
    }

    @Test("different sessions never share state")
    func whenDifferentSessions_thenIsolated() {
        let sessionA = "tests-session-a"
        let sessionB = "tests-session-b"
        let storeA = AppDefaults.makeStore(for: configuration(mode: .uiTest, session: sessionA))
        let storeB = AppDefaults.makeStore(for: configuration(mode: .uiTest, session: sessionB))

        storeA.set(true, forKey: "flag")

        #expect(storeB.object(forKey: "flag") == nil)
    }

    @Test("a uiTest launch with a work directory keeps its preferences inside it, so they go when the directory does")
    func whenWorkDirectory_thenPreferencesLiveInsideIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-defaults-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var config = configuration(mode: .uiTest, session: "tests-in-directory")
        config.directory = directory

        let store = AppDefaults.makeStore(for: config)
        store.set("value", forKey: "probe")
        store.synchronize()

        #expect(store !== UserDefaults.standard)
        #expect(store.string(forKey: "probe") == "value")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasSuffix(".plist") }, "\(files)")
    }

    @Test("a launch without a work directory keeps its preferences in the temporary folder, not ~/Library/Preferences")
    func whenNoWorkDirectory_thenPreferencesLiveInTheTemporaryFolder() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-defaults-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        for mode in [LaunchMode.hostedTests, .uiTest] {
            let store = AppDefaults.makeStore(
                for: configuration(mode: mode, session: "tests-temporary-\(mode)"), temporary: temporary
            )
            store.set("value", forKey: "probe")
            store.synchronize()
            #expect(store.string(forKey: "probe") == "value")
        }

        let found = try #require(FileManager.default.enumerator(at: temporary, includingPropertiesForKeys: nil))
            .compactMap { ($0 as? URL)?.lastPathComponent }.filter { $0.hasSuffix(".plist") }
        #expect(found.count == 2, "\(found)")
    }
}

// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("RuntimeConfiguration parsing")
struct RuntimeConfigurationTests {
    private func parse(_ arguments: [String], _ environment: [String: String] = [:]) -> RuntimeConfiguration {
        RuntimeConfiguration.parse(arguments: ["Pesto"] + arguments, environment: environment)
    }

    @Test("a UI-test launch can name a fixture library for the import sheet, and a normal launch never reads it")
    func whenImportFixture_thenOnlyInUITestMode() {
        #expect(parse(["-UITestMode"]).importFixture == nil)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_IMPORT_FIXTURE": "maccy"]).importFixture == "maccy")
        #expect(parse([], ["PESTO_UITEST_IMPORT_FIXTURE": "maccy"]).importFixture == nil)
    }

    @Test("a UI-test launch can force the lost-key flow, and a normal launch never does")
    func whenKeyLossFixture_thenOnlyInUITestMode() {
        #expect(!parse(["-UITestMode"]).keyLossFixture)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_KEYLOSS": "1"]).keyLossFixture)
        #expect(!parse(["-UITestMode"], ["PESTO_UITEST_KEYLOSS": "0"]).keyLossFixture)
        #expect(!parse([], ["PESTO_UITEST_KEYLOSS": "1"]).keyLossFixture)
    }

    @Test("a UI-test launch can swap in a fake model for the AI panel, and a normal launch never does")
    func whenAIFixture_thenOnlyInUITestMode() {
        #expect(!parse(["-UITestMode"]).aiFixture)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_AI_FIXTURE": "1"]).aiFixture)
        #expect(!parse([], ["PESTO_UITEST_AI_FIXTURE": "1"]).aiFixture)
    }

    @Test("a UI-test launch can report hotkeys live to the suggestion policy, and a normal launch never does")
    func whenSuggestionsLive_thenOnlyInUITestMode() {
        #expect(!parse(["-UITestMode"]).suggestionsLive)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_SUGGESTIONS_LIVE": "1"]).suggestionsLive)
        #expect(!parse([], ["PESTO_UITEST_SUGGESTIONS_LIVE": "1"]).suggestionsLive)
    }

    @Test("the suggestion seed is three clips and the first is the one the harness gives pastes")
    func whenSuggestionSeed_thenFirstCaptureIsTheSuggestionClip() {
        #expect(SeedFixtures.captures(for: .suggestion).count == 3)
        #expect(SeedProfile(rawValue: "suggestion") == .suggestion)
    }

    @Test("a normal launch carries no test configuration")
    func whenNormalLaunch_thenDefaults() {
        let config = parse([])
        #expect(config.mode == .normal)
        #expect(config.session == "default")
        #expect(config.seed == .basic)
        #expect(config.accessibility == .trusted)
    }

    @Test("session, seed and accessibility come from the environment in uiTest mode")
    func whenUITestEnvironment_thenParsed() {
        let config = parse(["-UITestMode"], [
            "PESTO_UITEST_SESSION": "run-42",
            "PESTO_UITEST_SEED": "large",
            "PESTO_UITEST_ACCESSIBILITY": "denied"
        ])
        #expect(config.mode == .uiTest)
        #expect(config.session == "run-42")
        #expect(config.seed == .large)
        #expect(config.accessibility == .denied)
    }

    @Test("an unrecognised seed or accessibility value falls back to the defaults")
    func whenUnknownValues_thenDefaults() {
        let config = parse(["-UITestMode"], [
            "PESTO_UITEST_SEED": "nonsense",
            "PESTO_UITEST_ACCESSIBILITY": "maybe"
        ])
        #expect(config.seed == .basic)
        #expect(config.accessibility == .trusted)
    }

    @Test("an empty session id falls back to the default so the suite name stays valid")
    func whenEmptySession_thenDefault() {
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_SESSION": ""]).session == "default")
    }

    @Test("test environment variables are ignored outside uiTest mode")
    func whenNotUITest_thenEnvironmentIgnored() {
        let config = parse([], ["PESTO_UITEST_SEED": "large", "PESTO_UITEST_ACCESSIBILITY": "denied"])
        #expect(config.seed == .basic)
        #expect(config.accessibility == .trusted)
    }

    @Test("PESTO_UITEST_PERF_TIMELINE asks for the timeline file in uiTest mode only")
    func perfTimeline_isUITestOnly() {
        #expect(parse(["-UITestMode"]).recordsPerfTimeline == false)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_PERF_TIMELINE": "1"]).recordsPerfTimeline == true)
        #expect(parse([], ["PESTO_UITEST_PERF_TIMELINE": "1"]).recordsPerfTimeline == false)
    }

    @Test("PESTO_UITEST_REAL_PASTE asks for the real clipboard in uiTest mode only")
    func whenRealPasteRequested_thenOnlyUITestHonoursIt() {
        #expect(parse(["-UITestMode"]).usesRealPasteboard == false)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_REAL_PASTE": "1"]).usesRealPasteboard == true)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_REAL_PASTE": "0"]).usesRealPasteboard == false)
        #expect(parse([], ["PESTO_UITEST_REAL_PASTE": "1"]).usesRealPasteboard == false)
    }

    @Test("PESTO_UITEST_REAL_DEVICE asks for Touch ID and the on-device model in uiTest mode only")
    func whenRealDeviceRequested_thenOnlyUITestHonoursIt() {
        #expect(parse(["-UITestMode"]).usesRealDevice == false)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_REAL_DEVICE": "1"]).usesRealDevice == true)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_REAL_DEVICE": "0"]).usesRealDevice == false)
        #expect(parse([], ["PESTO_UITEST_REAL_DEVICE": "1"]).usesRealDevice == false)
    }

    @Test("the working directory comes from PESTO_UITEST_DIR in uiTest mode")
    func whenUITestDirectory_thenParsed() {
        let config = parse(["-UITestMode"], ["PESTO_UITEST_DIR": "/tmp/pesto-run-1"])
        #expect(config.directory?.path == "/tmp/pesto-run-1")
    }

    @Test("a working directory outside the temporary directory is refused, so the harness cannot touch a real store")
    func whenDirectoryIsARealDataFolder_thenRefused() {
        let support = NSHomeDirectory() + "/Library/Application Support/net.copypesto.pesto"
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_DIR": support]).directory == nil)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_DIR": NSHomeDirectory() + "/Documents"]).directory == nil)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_DIR": "/tmp/../Users/x"]).directory == nil)
    }

    @Test("a folder made for a test run is accepted, wherever the runner's temporary directory is")
    func whenDirectoryIsATestFolder_thenAccepted() {
        let container = NSHomeDirectory() + "/Library/Containers/com.apple.dt.xctest.tool/Data/tmp/pesto-uitest-ui-1a2b"
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_DIR": container]).directory != nil)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_DIR": NSTemporaryDirectory() + "pesto-run-2"]).directory != nil)
    }

    @Test("a test folder inside Application Support is still refused")
    func whenTestFolderIsInsideApplicationSupport_thenRefused() {
        let inside = NSHomeDirectory() + "/Library/Application Support/pesto-uitest-x"
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_DIR": inside]).directory == nil)
    }

    @Test("an empty or missing working directory is nil so the temporary directory is used")
    func whenNoUITestDirectory_thenNil() {
        #expect(parse(["-UITestMode"]).directory == nil)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_DIR": ""]).directory == nil)
    }

    @Test("preference overrides come from PESTO_UITEST_DEFAULT_ variables with typed values")
    func whenDefaultOverrides_thenTypedValuesParsed() {
        let config = parse(["-UITestMode"], [
            "PESTO_UITEST_DEFAULT_hasOnboarded": "true",
            "PESTO_UITEST_DEFAULT_nsfwFilterEnabled": "false",
            "PESTO_UITEST_DEFAULT_biometricLockTimeoutMinutes": "5",
            "PESTO_UITEST_DEFAULT_appearanceMode": "dark"
        ])
        #expect(config.defaultOverrides["hasOnboarded"] == .bool(true))
        #expect(config.defaultOverrides["nsfwFilterEnabled"] == .bool(false))
        #expect(config.defaultOverrides["biometricLockTimeoutMinutes"] == .int(5))
        #expect(config.defaultOverrides["appearanceMode"] == .string("dark"))
    }

    @Test("preference overrides are ignored outside uiTest mode")
    func whenNotUITest_thenNoDefaultOverrides() {
        #expect(parse([], ["PESTO_UITEST_DEFAULT_hasOnboarded": "true"]).defaultOverrides.isEmpty)
    }

    @Test("the pasteboard name is scoped to the session so parallel runs cannot collide")
    func pasteboardName_isSessionScoped() {
        let config = parse(["-UITestMode"], ["PESTO_UITEST_SESSION": "run-42"])
        #expect(config.pasteboardName == "io.pesto.uitest.run-42")
    }

    @Test("a screenshot backdrop is honoured only in UI-test mode")
    func whenBackdropRequested_thenOnlyInUITestMode() {
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_BACKDROP": "hero"]).backdrop == .hero)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_BACKDROP": "plain"]).backdrop == .plain)
        #expect(parse(["-UITestMode"], ["PESTO_UITEST_BACKDROP": "garish"]).backdrop == .none)
        #expect(parse(["-UITestMode"]).backdrop == .none)
        #expect(parse([], ["PESTO_UITEST_BACKDROP": "hero"]).backdrop == .none, "a normal launch never draws one")
    }
}

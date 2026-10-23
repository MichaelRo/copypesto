// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("LaunchMode detection")
struct LaunchModeTests {
    @Test("a plain launch is normal")
    func whenNoTestMarkers_thenNormal() {
        #expect(LaunchMode.detect(arguments: ["Pesto"], environment: [:]) == .normal)
    }

    @Test("an XCTest host process is hostedTests")
    func whenXCTestConfigurationPresent_thenHostedTests() {
        let mode = LaunchMode.detect(
            arguments: ["Pesto"],
            environment: ["XCTestConfigurationFilePath": "/tmp/PestoTests.xctestconfiguration"]
        )
        #expect(mode == .hostedTests)
    }

    @Test("Xcode 27 host: empty configuration path, bundle path and session id set")
    func whenXcode27HostEnvironment_thenHostedTests() {
        let mode = LaunchMode.detect(arguments: ["Pesto"], environment: [
            "XCTestConfigurationFilePath": "",
            "XCTestBundlePath": "Contents/PlugIns/PestoTests.xctest",
            "XCTestSessionIdentifier": "7015B3BE-A496-4275-B61E-2207BBB25323"
        ])
        #expect(mode == .hostedTests)
    }

    @Test("empty XCTest variables alone do not count as a test host")
    func whenXCTestVariablesAllEmpty_thenNormal() {
        let mode = LaunchMode.detect(arguments: ["Pesto"], environment: [
            "XCTestConfigurationFilePath": "",
            "XCTestBundlePath": "",
            "XCTestSessionIdentifier": ""
        ])
        #expect(mode == .normal)
    }

    @Test("-UITestMode selects uiTest")
    func whenUITestModeArgument_thenUITest() {
        #expect(LaunchMode.detect(arguments: ["Pesto", "-UITestMode"], environment: [:]) == .uiTest)
    }

    @Test("-UITestMode wins over XCTest markers inherited from the runner")
    func whenUITestModeAndXCTestMarkers_thenUITest() {
        let mode = LaunchMode.detect(
            arguments: ["Pesto", "-UITestMode"],
            environment: ["XCTestSessionIdentifier": "7015B3BE"]
        )
        #expect(mode == .uiTest)
    }

    @Test("-UITestMode is ignored by a build that does not allow test hooks, so a shipped app cannot be put in it")
    func whenTestHooksAreNotAllowed_thenTheFlagIsIgnored() {
        let arguments = ["Pesto", "-UITestMode"]

        #expect(LaunchMode.detect(arguments: arguments, environment: [:], allowsTestHooks: false) == .normal)
        #expect(LaunchMode.detect(
            arguments: arguments, environment: ["XCTestBundlePath": "/x"], allowsTestHooks: false
        ) == .hostedTests)
        #expect(RuntimeConfiguration.parse(arguments: arguments, environment: [
            "PESTO_UITEST_SESSION": "s", "PESTO_UITEST_SEED": "large"
        ], allowsTestHooks: false).mode == .normal)
    }

    @Test("a build allows test hooks only when its Info.plist says YES")
    func whenReadingTheInfoDictionary_thenOnlyYesAllowsHooks() {
        #expect(TestHooks.allowed(infoDictionary: ["PestoAllowsTestHooks": "YES"]))
        #expect(!TestHooks.allowed(infoDictionary: ["PestoAllowsTestHooks": "NO"]))
        #expect(!TestHooks.allowed(infoDictionary: ["PestoAllowsTestHooks": ""]))
        #expect(!TestHooks.allowed(infoDictionary: [:]))
        #expect(!TestHooks.allowed(infoDictionary: nil))
    }

    @Test("the app boots in normal and uiTest launches but not in a hosted test run")
    func bootsAppServices_perMode() {
        #expect(LaunchMode.normal.bootsAppServices)
        #expect(LaunchMode.uiTest.bootsAppServices)
        #expect(!LaunchMode.hostedTests.bootsAppServices)
    }

    @Test("only a normal launch touches real system integrations")
    func usesSystemIntegrations_perMode() {
        #expect(LaunchMode.normal.usesSystemIntegrations)
        #expect(!LaunchMode.uiTest.usesSystemIntegrations)
        #expect(!LaunchMode.hostedTests.usesSystemIntegrations)
    }

    @Test("the processes `swift test` runs tests in are test hosts, so they cannot touch the real support folder")
    func whenSwiftPMTestProcess_thenHostedTests() {
        for program in [
            "/usr/libexec/swift/pm/swiftpm-testing-helper",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/xctest"
        ] {
            #expect(LaunchMode.detect(arguments: [program], environment: [:]) == .hostedTests)
        }
        #expect(LaunchMode
            .detect(arguments: ["/Applications/Pesto.app/Contents/MacOS/Pesto"], environment: [:]) == .normal)
    }
}

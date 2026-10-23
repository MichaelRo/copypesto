// SPDX-License-Identifier: MIT
import Foundation

public enum LaunchMode: Equatable, Sendable {
    case normal
    /// The process is Pesto.app acting as the XCTest host for PestoTests / PestoSnapshotTests.
    case hostedTests
    /// Launched by XCUITest with `-UITestMode`: real UI, isolated data, no system integrations.
    case uiTest

    public static var current: LaunchMode {
        RuntimeConfiguration.current.mode
    }

    static let uiTestArgument = "-UITestMode"

    /// Xcode 27 sets XCTestConfigurationFilePath to "" for hosted runs and signals the host through
    /// XCTestBundlePath / XCTestSessionIdentifier instead, so any one non-empty marker counts.
    private static let hostMarkers = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]

    /// `swift test` runs the tests in `xctest` or `swiftpm-testing-helper` and sets none of the markers above, so those
    /// processes counted as a normal launch and wrote to the real support folder.
    private static func isSwiftPMTestProcess(_ arguments: [String]) -> Bool {
        guard let program = arguments.first.map({ ($0 as NSString).lastPathComponent }) else { return false }
        return program == "xctest" || program == "swiftpm-testing-helper"
    }

    public static func detect(
        arguments: [String],
        environment: [String: String],
        allowsTestHooks: Bool = true
    )
    -> LaunchMode {
        // A UI-test launch can inherit XCTest markers from the runner; the explicit flag wins, in a build that allows
        // it.
        if allowsTestHooks, arguments.contains(uiTestArgument) { return .uiTest }
        let isTestHost = hostMarkers.contains { environment[$0].map { !$0.isEmpty } ?? false }
            || isSwiftPMTestProcess(arguments)
        return isTestHost ? .hostedTests : .normal
    }

    /// Storage, the watcher and the UI start in a normal or UI-test launch, never in a test host.
    public var bootsAppServices: Bool {
        self != .hostedTests
    }

    /// Global hotkeys, Sparkle, the real Keychain key, real Accessibility checks and the system
    /// pasteboard act on the user's machine, so only a normal launch may use them.
    public var usesSystemIntegrations: Bool {
        self == .normal
    }
}

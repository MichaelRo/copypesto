// SPDX-License-Identifier: MIT
import AppKit

/// Which of the import sources are installed on this Mac.
public protocol ClipboardAppDetecting: Sendable {
    func installed() -> [ImportSource]
}

public typealias WorkspaceAppLookup = @Sendable (String) -> URL?

/// Asks LaunchServices for each bundle identifier. It never opens another app's container.
public struct LaunchServicesAppDetector: ClipboardAppDetecting {
    private let lookup: WorkspaceAppLookup

    public init(
        lookup: @escaping WorkspaceAppLookup = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    ) {
        self.lookup = lookup
    }

    public func installed() -> [ImportSource] {
        ImportSource.allCases.filter { source in
            source.bundleIDs.contains { lookup($0) != nil }
        }
    }
}

/// What a UI-test launch finds: the apps its fixture names, a comma-separated list
/// (`RuntimeConfiguration.importFixture`), or nothing. A
/// hosted test or a normal launch never uses it.
public struct FixtureAppDetector: ClipboardAppDetecting {
    public let fixture: String?

    public init(fixture: String?) {
        self.fixture = fixture
    }

    public func installed() -> [ImportSource] {
        let named = Set(ImportFixture.names(in: fixture))
        return ImportSource.allCases.filter { named.contains($0.rawValue) }
    }
}

public enum ClipboardAppDetection {
    /// The detector for this launch: LaunchServices in a normal one, the fixture in a UI-test one, and none elsewhere.
    public static func forThisLaunch() -> any ClipboardAppDetecting {
        let configuration = RuntimeConfiguration.current
        switch configuration.mode {
        case .normal: return LaunchServicesAppDetector()
        case .uiTest: return FixtureAppDetector(fixture: configuration.importFixture)
        default: return FixtureAppDetector(fixture: nil)
        }
    }
}

// SPDX-License-Identifier: MIT
import Foundation

public enum SeedProfile: String, Equatable, Sendable {
    case empty
    case basic
    case large
    /// A few file clips: one that exists, one that has gone, and a group.
    case files
    /// Pesto-themed sample clips for the README, docs and website screenshots.
    case showcase
    /// The website screenshots: Apple-app sources only, two collections and a snippet (`MarketingSeed`).
    case marketing
    /// A long, varied history with large pictures, for measuring scrolling (`MixedSeed`).
    case mixed
    /// A copied animated GIF between two text clips, to check that the shelf plays it (`SeedFixtures`).
    case animated
    /// Two clips copied on this Mac and one that came from another device (`SeedFixtures`).
    case remote
    /// One clip of each kind, for `scripts/bench-latency.sh` (`LatencySeed`).
    case latency
    /// Only large pictures, for measuring memory over a shelf scrolled through to its end (`MixedSeed`).
    case pictures
    /// Three text clips, one of them pasted often enough for a shortcut offer (`SeedFixtures.suggestionClipID`).
    case suggestion
}

public enum AccessibilityStub: String, Equatable, Sendable {
    case trusted
    case denied
}

public enum DefaultsValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case string(String)

    init(parsing raw: String) {
        if raw == "true" || raw == "false" {
            self = .bool(raw == "true")
        } else if let number = Int(raw) {
            self = .int(number)
        } else {
            self = .string(raw)
        }
    }
}

/// A branded window drawn behind the shelf for website screenshots, so the translucent glass shows the palette and
/// not whatever happens to be on the capture Mac's desktop. Only ever honoured in UI-test mode.
public enum MarketingBackdropStyle: String, Equatable, Sendable {
    case none
    case plain
    case hero
}

public struct RuntimeConfiguration: Equatable, Sendable {
    public var mode: LaunchMode
    public var session: String
    public var seed: SeedProfile
    public var accessibility: AccessibilityStub
    /// Working directory chosen by the test runner (PESTO_UITEST_DIR); shared by the app and the runner.
    public var directory: URL?
    /// Preferences the runner wants set before launch (PESTO_UITEST_DEFAULT_<key>), e.g. dark appearance.
    public var defaultOverrides: [String: DefaultsValue]
    public var backdrop: MarketingBackdropStyle
    /// The latency bench (`scripts/bench-latency.sh`) pastes into a real app, so it reads and writes the system
    /// clipboard and posts real keystrokes. Honoured in UI-test mode only; the bench restores the clipboard it finds.
    public var usesRealPasteboard: Bool
    /// Writes `perf-timeline.tsv` without taking over the clipboard (`scripts/profile-scroll.sh` reads the shelf's
    /// scroll
    /// offsets from it). UI-test mode only.
    public var recordsPerfTimeline: Bool
    /// The documentation pictures of the Touch ID lock and of Ask Pesto need the real thing: the system's own Touch ID
    /// view and Apple's on-device model. Honoured in UI-test mode only, and only with a person at the Mac
    /// (`make capture-real`); everything else about the run stays isolated.
    public var usesRealDevice: Bool
    /// Names a fixture library (`maccy`, `alfred`, `paste`) that the import menu shows instead of opening a file panel,
    /// which a UI test cannot drive. UI-test mode only; `ImportFixture` makes the library.
    public var importFixture: String?
    /// Forces the "can't unlock your history" flow with a backup the app writes itself (`KeyLossFixture`), because the
    /// real one needs a missing Keychain key and the restore window needs a file panel, neither of which a UI test can
    /// make. UI-test mode only.
    public var keyLossFixture: Bool
    /// Swaps the on-device model for a fake that answers at once, so a UI test can drive the AI panel on any Mac.
    /// UI-test
    /// mode only.
    public var aiFixture: Bool
    /// Makes the shelf-suggestion policy see global hotkeys as live, which a UI-test launch never registers. Nothing is
    /// registered by it. UI-test mode only.
    public var suggestionsLive: Bool

    static let defaultOverridePrefix = "PESTO_UITEST_DEFAULT_"

    public static let defaultSession = "default"

    public init(
        mode: LaunchMode,
        session: String,
        seed: SeedProfile,
        accessibility: AccessibilityStub,
        directory: URL? = nil,
        defaultOverrides: [String: DefaultsValue] = [:],
        backdrop: MarketingBackdropStyle = .none,
        usesRealPasteboard: Bool = false,
        recordsPerfTimeline: Bool = false,
        usesRealDevice: Bool = false,
        importFixture: String? = nil,
        keyLossFixture: Bool = false,
        aiFixture: Bool = false,
        suggestionsLive: Bool = false
    ) {
        self.mode = mode
        self.session = session
        self.seed = seed
        self.accessibility = accessibility
        self.directory = directory
        self.defaultOverrides = defaultOverrides
        self.backdrop = backdrop
        self.usesRealPasteboard = usesRealPasteboard
        self.recordsPerfTimeline = recordsPerfTimeline
        self.usesRealDevice = usesRealDevice
        self.importFixture = importFixture
        self.keyLossFixture = keyLossFixture
        self.aiFixture = aiFixture
        self.suggestionsLive = suggestionsLive
    }

    public static let current = parse(
        arguments: CommandLine.arguments,
        environment: ProcessInfo.processInfo.environment,
        allowsTestHooks: TestHooks.allowedInThisBuild
    )

    public static func parse(
        arguments: [String],
        environment: [String: String],
        allowsTestHooks: Bool = true
    )
    -> RuntimeConfiguration {
        let mode = LaunchMode.detect(arguments: arguments, environment: environment, allowsTestHooks: allowsTestHooks)
        guard mode == .uiTest else {
            return RuntimeConfiguration(mode: mode, session: defaultSession, seed: .basic, accessibility: .trusted)
        }
        let session = environment["PESTO_UITEST_SESSION"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultSession
        return RuntimeConfiguration(
            mode: mode,
            session: session,
            seed: environment["PESTO_UITEST_SEED"].flatMap(SeedProfile.init(rawValue:)) ?? .basic,
            accessibility: environment["PESTO_UITEST_ACCESSIBILITY"].flatMap(AccessibilityStub.init(rawValue:))
                ?? .trusted,
            directory: environment["PESTO_UITEST_DIR"].flatMap(temporaryDirectory(from:)),
            defaultOverrides: parseOverrides(environment),
            backdrop: environment["PESTO_UITEST_BACKDROP"].flatMap(MarketingBackdropStyle.init(rawValue:)) ?? .none,
            usesRealPasteboard: environment["PESTO_UITEST_REAL_PASTE"] == "1",
            recordsPerfTimeline: environment["PESTO_UITEST_PERF_TIMELINE"] == "1",
            usesRealDevice: environment["PESTO_UITEST_REAL_DEVICE"] == "1",
            importFixture: environment["PESTO_UITEST_IMPORT_FIXTURE"].flatMap { $0.isEmpty ? nil : $0 },
            keyLossFixture: environment["PESTO_UITEST_KEYLOSS"] == "1",
            aiFixture: environment["PESTO_UITEST_AI_FIXTURE"] == "1",
            suggestionsLive: environment["PESTO_UITEST_SUGGESTIONS_LIVE"] == "1"
        )
    }

    /// The harness seeds fake clips and reads command files from this folder, so it may only point at a folder made
    /// for a test run (named `pesto-...`, and never inside Application Support), not at a real store. The UI-test
    /// runner is sandboxed and its temporary directory is not the app's, so "inside the temporary directory" cannot
    /// be the rule.
    private static func temporaryDirectory(from path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.lastPathComponent.hasPrefix("pesto-"),
              !candidate.path.contains("/Library/Application Support/") else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func parseOverrides(_ environment: [String: String]) -> [String: DefaultsValue] {
        var overrides: [String: DefaultsValue] = [:]
        for (name, raw) in environment where name.hasPrefix(defaultOverridePrefix) {
            let key = String(name.dropFirst(defaultOverridePrefix.count))
            if !key.isEmpty { overrides[key] = DefaultsValue(parsing: raw) }
        }
        return overrides
    }

    /// Named pasteboard that stands in for `NSPasteboard.general` in UI-test mode.
    public var pasteboardName: String {
        "io.pesto.uitest.\(session)"
    }
}

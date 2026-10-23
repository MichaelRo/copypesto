// SPDX-License-Identifier: MIT
import Foundation

/// The single access point for Pesto's user preferences. Anything outside a normal launch gets a
/// private suite, so tests can flip any setting without writing to the user's real preferences.
public enum AppDefaults {
    /// UserDefaults is documented thread-safe but not annotated Sendable; the reference never changes.
    public nonisolated(unsafe) static let store = makeStore(for: RuntimeConfiguration.current)

    static func makeStore(
        for configuration: RuntimeConfiguration,
        temporary: URL = FileManager.default.temporaryDirectory
    )
    -> UserDefaults {
        guard configuration.mode != .normal else { return .standard }
        // A suite named by a path keeps its file there. The runner removes its work directory when the test ends, and
        // a hosted run uses a session folder in the temporary directory, so the preferences never pile up in
        // ~/Library/Preferences (a plain named suite leaves a plist there that removePersistentDomain does not delete).
        let directory = AppPaths.supportDirectory(
            for: configuration, applicationSupport: temporary, temporary: temporary
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = directory.appendingPathComponent("defaults").path
        guard let suite = UserDefaults(suiteName: name) else {
            // Falling back to .standard here would put test writes in the user's real preferences.
            preconditionFailure("Isolated defaults suite unavailable for session \(configuration.session)")
        }
        for (key, value) in configuration.defaultOverrides {
            switch value {
            case let .bool(flag): suite.set(flag, forKey: key)
            case let .int(number): suite.set(number, forKey: key)
            case let .string(text): suite.set(text, forKey: key)
            }
        }
        return suite
    }
}

// SPDX-License-Identifier: MIT
import Foundation

/// A preferences domain for one test, kept in a temporary folder instead of `~/Library/Preferences`.
/// A named suite there leaves a plist behind even after `removePersistentDomain`, which put ten thousand files in the
/// real preferences folder; a suite named by an absolute path keeps its plist at that path, and the folder is removed
/// when the test process exits. Never use a bundle ID or any other real domain name in a test.
enum ThrowawayDefaults {
    private static let directory: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "pesto-test-defaults-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        atexit { ThrowawayDefaults.removeAll() }
        return url
    }()

    private static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The domain name to hand to code that takes one (such as `persistentDomain(forName:)`).
    static func domain(_ name: String) -> String {
        directory.appendingPathComponent(name).path
    }

    /// A fresh domain, or the same one again for the same `name`.
    static func make(_ name: String = UUID().uuidString) -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: domain(name)) else {
            preconditionFailure("no defaults suite for \(name)")
        }
        return defaults
    }
}

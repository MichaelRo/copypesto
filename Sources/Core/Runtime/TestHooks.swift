// SPDX-License-Identifier: MIT
import Foundation

/// Whether this build may be driven by the UI-test harness (`-UITestMode`, a work directory, seeded clips and a
/// command file). The Debug build the tests run and the Profile build the scroll benchmarks use say YES in their
/// Info.plist (`PESTO_ALLOWS_TEST_HOOKS`); a Release build says NO, so no shipped app can be put in that mode by its
/// launch arguments.
public enum TestHooks {
    static let infoKey = "PestoAllowsTestHooks"

    public static func allowed(infoDictionary: [String: Any]?) -> Bool {
        infoDictionary?[infoKey] as? String == "YES"
    }

    public static let allowedInThisBuild = allowed(infoDictionary: Bundle.main.infoDictionary)
}

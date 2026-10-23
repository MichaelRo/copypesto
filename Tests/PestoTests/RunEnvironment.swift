// SPDX-License-Identifier: MIT
import Foundation

enum RunEnvironment {
    /// Hardware budgets (milliseconds, megabytes) are calibrated on a developer Mac; shared CI runners are slower and
    /// noisier, so those assertions run locally. The measurements still execute on CI.
    static let isCI = ProcessInfo.processInfo.environment["PESTO_CI"] != nil || ProcessInfo.processInfo
        .environment["CI"] != nil
}

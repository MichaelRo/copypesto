// SPDX-License-Identifier: MIT
import Foundation

enum HostedRunner {
    /// A hosted CI runner is a virtual machine with three cores and no window-server session, so tests that need real
    /// hardware or AppKit's document importers do not run there.
    static let isActive = ProcessInfo.processInfo.environment["CI"] != nil
        || ProcessInfo.processInfo.environment["PESTO_CI"] != nil
}

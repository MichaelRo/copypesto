// SPDX-License-Identifier: MIT
import AppKit
import CoreServices
import Foundation
import PestoCore
import Testing

extension HostedGlobals {
    @Suite("ImportOfferDetector", .serialized)
    @MainActor
    final class ImportOfferDetectorTests {
        @Test("WorkspaceAppLookup seam detects matching ImportSource entries without touching LaunchServices")
        func whenLookupMatchesBundleID_thenDetectsImportSource() throws {
            let expected = ImportSource.maccy
            let targetBundleID = try #require(expected.bundleIDs.first)

            let detector = LaunchServicesAppDetector { bundleID in
                bundleID == targetBundleID ? URL(fileURLWithPath: "/Applications/Maccy.app") : nil
            }
            #expect(detector.installed() == [expected])

            let empty = LaunchServicesAppDetector { _ in nil }
            #expect(empty.installed().isEmpty)
        }

        @Test("LaunchServicesAppDetector queries NSWorkspace without error and deduplicates sources")
        func whenLaunchServicesDetectorQueried_thenReturnsUniqueInstalledSources() {
            let detected = LaunchServicesAppDetector().installed()
            #expect(Set(detected).count == detected.count)
            for source in detected {
                let found = source.bundleIDs.contains {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
                }
                #expect(found)
            }
        }
    }
}

// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Entitlements and purpose strings")
struct EntitlementsTests {
    private func plist(_ relativePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("the release entitlements do not ask for Apple Events or a sandbox-only network entitlement")
    func releaseEntitlements_areMinimal() throws {
        let entitlements = try plist("Sources/Resources/Pesto.entitlements")

        #expect(entitlements["com.apple.security.automation.apple-events"] == nil)
        #expect(entitlements["com.apple.security.network.client"] == nil)
    }

    @Test("v1 ships without iCloud: no entitlement, so no provisioning profile is needed to sign it")
    func releaseEntitlements_haveNoICloud() throws {
        let entitlements = try plist("Sources/Resources/Pesto.entitlements")

        #expect(!entitlements.keys.contains { $0.contains("icloud") })
    }

    @Test("Info.plist has no Apple Events purpose string, since nothing sends Apple Events")
    func infoPlist_hasNoAppleEventsPurpose() throws {
        let info = try plist("Sources/Resources/Info.plist")

        #expect(info["NSAppleEventsUsageDescription"] == nil)
    }

    @Test("the app launches with the large-block cache of malloc off, which returned 110 MB after long copies")
    func infoPlist_turnsOffTheLargeBlockCache() throws {
        let info = try plist("Sources/Resources/Info.plist")
        let environment = try #require(info["LSEnvironment"] as? [String: String])

        // Undocumented libmalloc setting, measured with `make bench-latency memory`: the footprint after 200 long
        // copies
        // and 50 screenshots was 215 MB without it and 105 MB with it.
        #expect(environment["MallocLargeCache"] == "0")
    }
}

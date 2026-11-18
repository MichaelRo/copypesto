// SPDX-License-Identifier: MIT
import Foundation

public struct SourceAppRecord: Sendable, Equatable {
    /// The name of a bundle ID this Mac cannot resolve (an app that is not installed here, as with a synced clip).
    public static let unknownDisplayName = "Unknown app"
    public let bundleID: String
    public let displayName: String
    /// 48×48 PNG, ≤5 KB. Shared through `SourceIconCache`; ingest does not use it.
    public let iconData: Data
    /// Hex `"#RRGGBB"` — drives the overlay mesh-gradient glow.
    public let dominantColorHex: String

    public init(bundleID: String, displayName: String, iconData: Data, dominantColorHex: String) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.iconData = iconData
        self.dominantColorHex = dominantColorHex
    }
}

public protocol SourceAppResolving: Sendable {
    func resolve(bundleID: String) async -> SourceAppRecord
}

/// For a platform that cannot look an app up by its bundle ID: every app is unknown, so a clip keeps the name it
/// arrived with.
public struct UnknownSourceApps: SourceAppResolving {
    public init() {}

    public func resolve(bundleID: String) async -> SourceAppRecord {
        SourceAppRecord(
            bundleID: bundleID, displayName: SourceAppRecord.unknownDisplayName, iconData: Data(),
            dominantColorHex: "#888888"
        )
    }
}

public enum SourceApps {
    public static func resolver() -> any SourceAppResolving {
        #if os(macOS)
        SourceAppResolver()
        #else
        UnknownSourceApps()
        #endif
    }
}

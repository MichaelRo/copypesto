// SPDX-License-Identifier: MIT
import Foundation

/// A local, offline announcement card/capsule that can be scheduled in `catalog` without any network calls
/// (ADR 0005). Dismissals persist by ID in `Setting.dismissedAnnouncementIDs`.
public struct AppAnnouncement: Identifiable, Sendable, Equatable {
    public enum Platform: String, Sendable, Hashable {
        case macOS
        case iOS
    }

    public let id: String
    public let symbol: String
    public let message: String
    public let primaryTitle: String
    public let actionURL: URL?
    public let secondaryTitle: String
    public let platforms: Set<Platform>
    public let window: DateInterval?
    public let minimumInstallAge: TimeInterval?
    public let minimumClipCount: Int

    public init(
        id: String,
        symbol: String = "megaphone",
        message: String,
        primaryTitle: String,
        actionURL: URL? = nil,
        secondaryTitle: String = String(localized: "Dismiss"),
        platforms: Set<Platform> = [.macOS, .iOS],
        window: DateInterval? = nil,
        minimumInstallAge: TimeInterval? = nil,
        minimumClipCount: Int = 0
    ) {
        self.id = id
        self.symbol = symbol
        self.message = message
        self.primaryTitle = primaryTitle
        self.actionURL = actionURL
        self.secondaryTitle = secondaryTitle
        self.platforms = platforms
        self.window = window
        self.minimumInstallAge = minimumInstallAge
        self.minimumClipCount = minimumClipCount
    }

    /// Compiled-in announcement catalog. Empty by default; add timed entries when shipping an announcement.
    public static let catalog: [AppAnnouncement] = []
}

public enum AnnouncementPolicy {
    public static func activeAnnouncement(
        from catalog: [AppAnnouncement] = AppAnnouncement.catalog,
        now: Date = .now,
        dismissedRaw: String,
        installDate: Date?,
        clipCount: Int,
        platform: AppAnnouncement.Platform,
        isLocked: Bool,
        hasOnboarded: Bool = true,
        isUITest: Bool = false
    )
    -> AppAnnouncement? {
        guard !isLocked, hasOnboarded, !isUITest else { return nil }
        let dismissed = dismissedIDs(from: dismissedRaw)
        return catalog.first { entry in
            guard !dismissed.contains(entry.id),
                  entry.platforms.contains(platform),
                  clipCount >= entry.minimumClipCount else { return false }
            if let window = entry.window, !window.contains(now) { return false }
            if let minAge = entry.minimumInstallAge {
                guard let installDate, now.timeIntervalSince(installDate) >= minAge else { return false }
            }
            return true
        }
    }

    public static func dismissedIDs(from raw: String) -> Set<String> {
        Set(
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    public static func dismissing(_ id: String, in raw: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        var ids = dismissedIDs(from: raw)
        if !trimmed.isEmpty { ids.insert(trimmed) }
        return ids.sorted().joined(separator: ",")
    }

    /// Only allows external `https:` links with a host; blocks custom schemes and local file URLs.
    public static func safeActionURL(for announcement: AppAnnouncement) -> URL? {
        guard let url = announcement.actionURL,
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty else { return nil }
        return url
    }
}

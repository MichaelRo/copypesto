// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Offline announcement banner policy")
struct AppAnnouncementTests {
    private let sample = AppAnnouncement(
        id: "release-highlight",
        symbol: "sparkles",
        message: "Pesto update highlight",
        primaryTitle: "Learn More",
        actionURL: URL(string: "https://copypesto.net"),
        platforms: [.macOS, .iOS],
        window: DateInterval(
            start: Date(timeIntervalSince1970: 1_000_000),
            end: Date(timeIntervalSince1970: 2_000_000)
        ),
        minimumInstallAge: 86_400,
        minimumClipCount: 5
    )

    @Test("catalog is empty by default so unscheduled builds show no banner")
    func whenDefaultCatalog_thenShowsNothing() {
        let active = AnnouncementPolicy.activeAnnouncement(
            now: .now,
            dismissedRaw: "",
            installDate: .distantPast,
            clipCount: 100,
            platform: .macOS,
            isLocked: false
        )
        #expect(active == nil)
    }

    @Test("matching window, platform, clip count, and install age surface the announcement")
    func whenAllGatesPass_thenReturnsAnnouncement() {
        let active = AnnouncementPolicy.activeAnnouncement(
            from: [sample],
            now: Date(timeIntervalSince1970: 1_500_000),
            dismissedRaw: "",
            installDate: Date(timeIntervalSince1970: 1_500_000 - 100_000),
            clipCount: 5,
            platform: .iOS,
            isLocked: false
        )
        #expect(active == sample)
    }

    @Test("out-of-window, locked, un-onboarded, UI-test, low clip count, or dismissed states suppress it")
    func whenAnyGateFails_thenSuppressed() {
        let validNow = Date(timeIntervalSince1970: 1_500_000)
        let oldInstall = Date(timeIntervalSince1970: 1_500_000 - 100_000)

        #expect(AnnouncementPolicy.activeAnnouncement(
            from: [sample], now: Date(timeIntervalSince1970: 500_000), dismissedRaw: "",
            installDate: oldInstall, clipCount: 10, platform: .macOS, isLocked: false
        ) == nil)
        #expect(AnnouncementPolicy.activeAnnouncement(
            from: [sample], now: Date(timeIntervalSince1970: 2_500_000), dismissedRaw: "",
            installDate: oldInstall, clipCount: 10, platform: .macOS, isLocked: false
        ) == nil)
        #expect(AnnouncementPolicy.activeAnnouncement(
            from: [sample], now: validNow, dismissedRaw: "release-highlight",
            installDate: oldInstall, clipCount: 10, platform: .macOS, isLocked: false
        ) == nil)
        #expect(AnnouncementPolicy.activeAnnouncement(
            from: [sample], now: validNow, dismissedRaw: "",
            installDate: oldInstall, clipCount: 4, platform: .macOS, isLocked: false
        ) == nil)
        #expect(AnnouncementPolicy.activeAnnouncement(
            from: [sample], now: validNow, dismissedRaw: "",
            installDate: validNow.addingTimeInterval(-3600), clipCount: 10, platform: .macOS, isLocked: false
        ) == nil)
        #expect(AnnouncementPolicy.activeAnnouncement(
            from: [sample], now: validNow, dismissedRaw: "",
            installDate: oldInstall, clipCount: 10, platform: .macOS, isLocked: true
        ) == nil)
        #expect(AnnouncementPolicy.activeAnnouncement(
            from: [sample], now: validNow, dismissedRaw: "",
            installDate: oldInstall, clipCount: 10, platform: .macOS, isLocked: false, hasOnboarded: false
        ) == nil)
        #expect(AnnouncementPolicy.activeAnnouncement(
            from: [sample], now: validNow, dismissedRaw: "",
            installDate: oldInstall, clipCount: 10, platform: .macOS, isLocked: false, isUITest: true
        ) == nil)
    }

    @Test("dismissing deduplicates and preserves earlier dismissed IDs, and only https URLs open")
    func whenDismissedAndCheckingURL_thenPersistsAndValidatesScheme() {
        let updated = AnnouncementPolicy.dismissing("b", in: "a, b")
        #expect(updated == "a,b")
        #expect(AnnouncementPolicy.dismissing("c", in: updated) == "a,b,c")

        #expect(AnnouncementPolicy.safeActionURL(for: sample) == URL(string: "https://copypesto.net"))
        let fileAnnouncement = AppAnnouncement(
            id: "bad", message: "x", primaryTitle: "Open", actionURL: URL(string: "file:///etc/passwd")
        )
        #expect(AnnouncementPolicy.safeActionURL(for: fileAnnouncement) == nil)
    }
}

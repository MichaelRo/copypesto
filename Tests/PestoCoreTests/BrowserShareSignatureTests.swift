// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

private struct DumpEntry: Decodable {
    let owner: String
    let pid: Int32
    let layer: Int
    let onscreen: Bool
    let alpha: Double
    let width: Double
    let height: Double
}

private struct Dump: Decodable {
    let windows: [DumpEntry]
}

@Suite("Browser share signature")
struct BrowserShareSignatureTests {
    private static let bundleIDsByOwner = [
        "Firefox": "org.mozilla.firefox",
        "Google Chrome": "com.google.Chrome",
        "Safari": "com.apple.Safari",
        "Window Tool": "com.example.windowtool"
    ]

    private func load(_ name: String) throws -> (windows: [WindowSnapshot], bundleID: @Sendable (Int32) -> String?) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        let dump = try JSONDecoder().decode(Dump.self, from: Data(contentsOf: url))
        let owners = Dictionary(dump.windows.map { ($0.pid, $0.owner) }, uniquingKeysWith: { first, _ in first })
        let windows = dump.windows.map {
            WindowSnapshot(
                ownerPID: $0.pid, layer: $0.layer, isOnScreen: $0.onscreen,
                width: $0.width, height: $0.height, alpha: $0.alpha
            )
        }
        return (windows, { pid in owners[pid].flatMap { Self.bundleIDsByOwner[$0] } })
    }

    @Test("an idle Mac with Chrome open is not sharing")
    func whenIdleDump_thenNotSharing() throws {
        let dump = try load("share-windows-idle")
        #expect(!BrowserShareSignature.isSharing(windows: dump.windows, bundleID: dump.bundleID))
    }

    @Test("Meet with camera and microphone active but not sharing is not sharing")
    func whenMeetActiveWithoutSharing_thenNotSharing() throws {
        let dump = try load("share-windows-meet-not-sharing")
        #expect(!BrowserShareSignature.isSharing(windows: dump.windows, bundleID: dump.bundleID))
    }

    @Test("Safari open in idle state is not sharing")
    func whenSafariIdleDump_thenNotSharing() throws {
        let dump = try load("share-windows-safari-idle")
        #expect(!BrowserShareSignature.isSharing(windows: dump.windows, bundleID: dump.bundleID))
    }

    @Test("Chrome's sharing bar while Meet shares the whole screen is sharing")
    func whenMeetChromeSharingDump_thenSharing() throws {
        let dump = try load("share-windows-meet-chrome-sharing")
        #expect(BrowserShareSignature.isSharing(windows: dump.windows, bundleID: dump.bundleID))
    }

    @Test("Firefox's floating sharing indicator bar is sharing, while its normal windows are not")
    func whenFirefoxSharingDump_thenSharing() throws {
        let dump = try load("share-windows-firefox-sharing")
        #expect(BrowserShareSignature.isSharing(windows: dump.windows, bundleID: dump.bundleID))
        let withoutBar = dump.windows.filter { $0.layer != 3 }
        #expect(!BrowserShareSignature.isSharing(windows: withoutBar, bundleID: dump.bundleID))
    }

    private let bar = WindowSnapshot(ownerPID: 7, layer: 25, isOnScreen: true, width: 439, height: 60, alpha: 0.96)

    @Test("the same bar from an app that is not a browser is not sharing")
    func whenBarBelongsToOtherApp_thenNotSharing() {
        #expect(!BrowserShareSignature.isSharing(windows: [bar], bundleID: { _ in "com.apple.finder" }))
        #expect(!BrowserShareSignature.isSharing(windows: [bar], bundleID: { _ in nil }))
    }

    @Test("a hidden bar, another layer or another size is not sharing")
    func whenShapeDiffers_thenNotSharing() {
        let chrome: @Sendable (Int32) -> String? = { _ in "com.google.Chrome" }
        var hidden = bar
        hidden.isOnScreen = false
        var floating = bar
        floating.layer = 3
        var tall = bar
        tall.height = 523
        var empty = bar
        empty.width = 0
        empty.height = 0
        for window in [hidden, floating, tall, empty] {
            #expect(!BrowserShareSignature.isSharing(windows: [window], bundleID: chrome))
        }
    }

    @Test("Chromium-family browsers all count", arguments: [
        "com.google.Chrome", "com.google.Chrome.beta", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium"
    ])
    func whenChromiumBrowser_thenSharing(bundleID: String) {
        #expect(BrowserShareSignature.isSharing(windows: [bar], bundleID: { _ in bundleID }))
    }
}

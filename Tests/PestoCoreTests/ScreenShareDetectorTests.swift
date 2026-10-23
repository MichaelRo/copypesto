// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Screen sharing detection")
struct ScreenShareDetectorTests {
    @Test("a running screen-sharing or recording app counts as sharing", arguments: [
        "us.zoom.xos", "com.apple.ScreenSharing", "com.microsoft.teams2", "com.obsproject.obs-studio",
        "com.apple.FaceTime", "com.loom.desktop", "com.hnc.Discord", "com.webex.meetingmanager"
    ])
    func whenSharingAppRunning_thenSharing(bundleID: String) {
        #expect(ScreenShareDetector.isSharing(runningBundleIDs: ["com.apple.finder", bundleID]))
    }

    @Test("the match ignores letter case")
    func whenBundleIDCaseDiffers_thenStillSharing() {
        #expect(ScreenShareDetector.isSharing(runningBundleIDs: ["com.apple.facetime"]))
        #expect(ScreenShareDetector.isSharing(runningBundleIDs: ["US.ZOOM.XOS"]))
    }

    @Test("ordinary apps do not, and neither does a browser that is merely open")
    func whenOnlyOrdinaryApps_thenNotSharing() {
        #expect(!ScreenShareDetector.isSharing(runningBundleIDs: [
            "com.apple.finder",
            "com.apple.Safari",
            "com.google.Chrome",
            "net.copypesto.pesto"
        ]))
        #expect(!ScreenShareDetector.isSharing(runningBundleIDs: []))
    }
}

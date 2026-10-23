// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Reports the shelf's horizontal scroll offset to the perf timeline, so `scripts/profile-scroll.sh` can fail a run in
/// which the shelf never moved: hitches are counted only while frames are produced, so a shelf that did not scroll
/// would otherwise read as a pass (P-06). Does nothing outside a bench launch (`PerfTimeline` is not recording).
private final class ScrollReport: @unchecked Sendable {
    private var last = -Double.infinity

    func note(_ offset: Double) {
        guard abs(offset - last) >= 8 else { return }
        last = offset
        PerfSignposts.shelf.event("shelfScroll", String(Int(offset)))
    }
}

extension View {
    func reportsScrollOffset() -> some View {
        modifier(ScrollOffsetReporter())
    }
}

private struct ScrollOffsetReporter: ViewModifier {
    @State private var report = ScrollReport()
    private let isRecording: Bool = {
        let configuration = RuntimeConfiguration.current
        return configuration.recordsPerfTimeline || configuration.usesRealPasteboard
    }()

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Double.self, of: { Double($0.contentOffset.x) }, action: { _, offset in
            if isRecording { report.note(offset) }
        })
    }
}

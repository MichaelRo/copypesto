// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

extension GridView {
    /// What the shelf does after an arrow key moved the focus: one place, so a benchmark drives the same code a key
    /// does.
    func arrowKeyMoved(isRepeat: Bool) {
        ActivityGate.shared.noteActivity()
        if isRepeat {
            if keyboardRevealedID != nil { keyboardRevealedID = nil }
            scrollToFocused(animated: false)
        } else {
            keyboardRevealedID = displayedItems.indices.contains(focusedIndex) ? displayedItems[focusedIndex].id : nil
            scrollToFocused(animated: true)
        }
    }

    /// UI-test only (`scripts/bench-shelf.sh`): moves the focus and switches collections as the keys do, and times
    /// each step to the commit that shows it. Each step's body counts land in the timeline as a `renders` event.
    func runBench(_ request: UITestBenchRequest) {
        Task { @MainActor in
            switch request.kind {
            case .arrowSteps: await benchArrows(count: 20, pauseMillis: 150, isRepeat: false)
            case .arrowHold: await benchArrows(count: 60, pauseMillis: 33, isRepeat: true)
            case .cycleCollections: await benchCollectionCycle(rounds: (pinboards.count + 1) * 2, pauseMillis: 600)
            case .cycleHold: await benchCollectionCycle(rounds: 40, pauseMillis: 33)
            case .cycleAB: await benchCycleAB()
            }
            let marker = AppPaths.supportDirectory.appendingPathComponent("bench-done")
            try? Data("\(request.serial)".utf8).write(to: marker)
        }
    }

    private func benchArrows(count: Int, pauseMillis: Int, isRepeat: Bool) async {
        focusedIndex = 0
        try? await Task.sleep(for: .milliseconds(500))
        RenderProbe.reset()
        for step in 0..<count where focusedIndex < displayedItems.count - 1 {
            let move = PerfSignposts.shelf.begin("focusMove")
            focusedIndex += 1
            arrowKeyMoved(isRepeat: isRepeat && step > 0)
            move.endAfterNextCommit()
            try? await Task.sleep(for: .milliseconds(pauseMillis))
            RenderProbe.report(after: "focusMove")
        }
    }

    /// Alternates the flags in `PESTO_AB_FLAGS` (comma separated) off and on, `rounds` times, one sweep through the
    /// collections each; every sweep starts with a `variant` event so `shelf_report.py` can tell the two apart.
    private func benchCycleAB() async {
        let flags = Set((ProcessInfo.processInfo.environment["PESTO_AB_FLAGS"] ?? "").split(separator: ",")
            .map(String.init))
        let sweep = pinboards.count + 1
        let abPause = Int(ProcessInfo.processInfo.environment["PESTO_AB_PAUSE_MS"] ?? "") ?? 500
        for _ in 0..<4 {
            for variant in ["A", "B"] {
                ShelfExperiments.shared.set(variant == "B" ? flags : [])
                try? await Task.sleep(for: .milliseconds(400))
                PerfSignposts.shelf.event("variant", variant)
                await benchCollectionCycle(rounds: sweep, pauseMillis: abPause)
            }
        }
        ShelfExperiments.shared.set([])
    }

    private func benchCollectionCycle(rounds: Int, pauseMillis: Int) async {
        try? await Task.sleep(for: .milliseconds(500))
        RenderProbe.reset()
        for _ in 0..<rounds {
            cyclePinboard(forward: true)
            try? await Task.sleep(for: .milliseconds(pauseMillis))
            RenderProbe.report(after: "collectionSwitch")
        }
    }
}

extension View {
    /// Counts a body run for `RenderProbe` and returns the view unchanged.
    func renderProbe(_ name: StaticString) -> some View {
        RenderProbe.hit(name)
        return self
    }
}

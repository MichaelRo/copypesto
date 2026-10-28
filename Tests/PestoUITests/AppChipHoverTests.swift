// SPDX-License-Identifier: MIT
import XCTest

/// The app chips on the command bar are icons at rest and show their name when the pointer rests on one. These tests
/// move a real pointer and look at what is on screen: the chip under the pointer opens, no other chip does, the chips
/// never overlap, and a pass across the row never lands the pointer on a chip it did not choose. A screenshot of the
/// steps is kept for a person to look at.
final class AppChipHoverTests: PestoUITestCase {
    private let restWidth: CGFloat = 28

    private var chips: [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'app-chip-'"))
            .allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func openChips(_ chips: [XCUIElement]) -> [Int] {
        chips.indices.filter { chips[$0].frame.width > restWidth + 12 }
    }

    private func point(x: CGFloat, y: CGFloat, in chip: XCUIElement) -> XCUICoordinate {
        chip.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - chip.frame.minX, dy: y))
    }

    /// A synthesized pointer jump is sometimes not delivered as a hover to a window it re-enters; two small moves are.
    private func hover(x: CGFloat, y: CGFloat, in chip: XCUIElement) {
        point(x: x - 3, y: y, in: chip).hover()
        point(x: x, y: y, in: chip).hover()
    }

    private func pointerIsOnTheOpenChips(_ x: CGFloat, _ current: [XCUIElement]) -> Bool {
        openChips(current).allSatisfy { current[$0].frame.minX - 6 <= x && x <= current[$0].frame.maxX + 6 }
    }

    private func prepare() -> [XCUIElement] {
        launch(seed: "marketing", defaults: ["hasOnboarded": "true"])
        showOverlay()
        let deadline = Date().addingTimeInterval(10)
        while chips.count < 3, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        parkPointer()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let found = chips
        XCTAssertGreaterThanOrEqual(found.count, 3, "the marketing seed should give at least three app chips")
        return found
    }

    private func assertNoOverlap(_ context: String) {
        let frames = chips.map(\.frame)
        for pair in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.maxX, pair.1.minX, "chips overlap \(context)")
        }
    }

    func test_restingOnAChip_opensOnlyThatChip_andNoChipsOverlap() {
        let found = prepare()
        let rest = found.map(\.frame)
        XCTAssertTrue(
            rest.allSatisfy { $0.width <= restWidth + 2 },
            "chips should be icons at rest: \(rest.map { [$0.minX, $0.width] })"
        )

        for index in found.indices {
            hover(x: rest[index].midX, y: rest[index].height / 2, in: found[index])
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            capture("chip-open-\(index)")

            XCTAssertEqual(openChips(chips), [index], "only chip \(index) should be open")
            assertNoOverlap("with chip \(index) open")
            parkPointer()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            XCTAssertTrue(openChips(chips).isEmpty, "the name stayed after the pointer left chip \(index)")
        }
    }

    func test_sweepingAcrossTheChips_neverLandsOnAChipItDidNotChoose() {
        let found = prepare()
        let rest = found.map(\.frame)
        let y = rest[0].height / 2
        for direction in [1.0, -1.0] {
            var x = direction > 0 ? rest[0].midX : rest[rest.count - 1].midX
            let stop = direction > 0 ? rest[rest.count - 1].midX : rest[0].midX
            var step = 0
            while direction > 0 ? x <= stop : x >= stop {
                point(x: x, y: y, in: found[0]).hover()
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                // Each element's frame is read separately, so a read that lands mid-switch can mix two moments: look
                // again.
                var current = chips
                if !pointerIsOnTheOpenChips(x, current) {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                    current = chips
                }
                XCTAssertTrue(
                    pointerIsOnTheOpenChips(x, current),
                    "x=\(x) is outside the open chip; frames \(current.map { [$0.frame.minX, $0.frame.width] })"
                )
                assertNoOverlap("during the sweep at x=\(x)")
                if step.isMultiple(of: 8) { capture("chip-sweep-\(direction > 0 ? "right" : "left")-\(step)") }
                x += 7 * direction
                step += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            XCTAssertEqual(openChips(chips).count, 1, "after the sweep one chip should be open")
            parkPointer()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
    }
}

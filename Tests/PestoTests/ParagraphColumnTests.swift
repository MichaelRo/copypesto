// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI
import Testing
@testable import Pesto

@Suite("ParagraphColumn")
@MainActor
struct ParagraphColumnTests {
    private static let width: CGFloat = 160

    private func height(budget: CGFloat, paragraphs: [String]) -> CGFloat {
        let column = ParagraphColumn(budget: budget) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                if index > 0 { ParagraphColumn.gap() }
                Text(paragraph).font(.body)
            }
        }
        .frame(width: Self.width)
        let controller = NSHostingController(rootView: column)
        return controller.sizeThatFits(in: CGSize(width: Self.width, height: 10_000)).height
    }

    private static let long = (1...12).map { "Line \($0) of a long note" }.joined(separator: "\n")

    @Test("one long paragraph is cut at the budget and fills most of it")
    func whenLong_thenCutAtBudget() {
        let result = height(budget: 90, paragraphs: [Self.long])
        #expect(result <= 90)
        #expect(result > 60, "the paragraph shows whole lines up to the budget, not a stub")
    }

    @Test("paragraphs stack with a 6 point gap between them when they fit")
    func whenFits_thenGapBetween() {
        let one = height(budget: 400, paragraphs: ["alpha"])
        let two = height(budget: 400, paragraphs: ["alpha", "beta"])
        #expect(abs(two - (2 * one + CardLayout.paragraphGap)) < 0.5)
    }

    @Test("paragraphs after the budget is spent are not laid out")
    func whenOverBudget_thenLaterOnesDropped() {
        let three = Array(repeating: "a\nb\nc", count: 3)
        #expect(height(budget: 90, paragraphs: three) <= 90)
        let alone = height(budget: 90, paragraphs: [Self.long])
        let withMore = height(budget: 90, paragraphs: [Self.long, "never shown"])
        #expect(withMore == alone)
    }
}

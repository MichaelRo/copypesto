// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The card's context menu reads the covered list")
struct CoveredMenuWiringTests {
    @Test("every CardMenuItem is asked for in the menu code, so none can bypass the covered list")
    func everyItemIsGated() throws {
        let source = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/ClipboardCard+ContextMenu.swift"),
            encoding: .utf8
        )
        for item in CardMenuItem.allCases {
            #expect(source.contains("offers(.\(item))"), "offers(.\(item)) is not in the menu code")
        }
    }
}

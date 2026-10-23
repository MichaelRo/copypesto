// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Shelf keyboard wiring")
struct KeyNavWiringTests {
    @Test("every action the keyboard coordinator can call is handed a handler by the wrapper (A-01)")
    func everyClosureIsAssigned() throws {
        let grid = SourceTree.sources.appendingPathComponent("Features/Grid")
        let coordinator = try String(
            contentsOf: grid.appendingPathComponent("KeyNavCoordinator.swift"), encoding: .utf8
        )
        let wrapper = try String(
            contentsOf: grid.appendingPathComponent("KeyboardNavigationWrapper.swift"), encoding: .utf8
        )
        let declared = try NSRegularExpression(pattern: #"^\s+var (on[A-Z]\w*):"#, options: [.anchorsMatchLines])
        let names = declared.matches(in: coordinator, range: NSRange(coordinator.startIndex..., in: coordinator))
            .compactMap { Range($0.range(at: 1), in: coordinator).map { String(coordinator[$0]) } }

        #expect(names.count > 30, "the scan found only \(names.count) handlers")
        let unassigned = names.filter { !wrapper.contains("coordinator.\($0) =") }
        #expect(unassigned.isEmpty, "the coordinator calls these but nothing sets them: \(unassigned)")
    }
}

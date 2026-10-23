// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("In-memory containers")
struct InMemoryContainerIsolationTests {
    @Test("two in-memory containers do not share rows, so parallel tests cannot see each other's collections")
    func whenTwoContainersAreMade_thenTheyAreIndependent() throws {
        let first = try ModelContainerSetup.makeInMemory().synced
        let second = try ModelContainerSetup.makeInMemory().synced

        let context = ModelContext(first)
        context.insert(Pinboard(name: "only in the first", symbolName: "star", colorHex: "#000000", sortOrder: 0))
        try context.save()

        #expect(try ModelContext(second).fetch(FetchDescriptor<Pinboard>()).isEmpty)
    }
}

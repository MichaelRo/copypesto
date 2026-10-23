// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Allowances are safe to touch from several threads")
struct ExclusionAllowancesConcurrencyTests {
    @Test("allowing and revoking from many tasks at once leaves exactly the apps that were allowed last")
    func whenManyTasks_thenConsistent() async {
        let backing = AllowanceStore()
        let ids = (0..<50).map { "com.example.app\($0)" }

        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { ExclusionAllowances(store: backing).allow(id, length: .untilQuit) }
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for id in ids.prefix(25) {
                group.addTask { ExclusionAllowances(store: backing).revoke(id) }
            }
        }

        #expect(Set(ExclusionAllowances(store: backing).active().keys) == Set(ids.suffix(25)))
    }
}

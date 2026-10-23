// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PestoCore

private struct Failure: Error {}

private final class Order: Sendable {
    private let names = Mutex<[String]>([])
    func add(_ name: String) {
        names.withLock { $0.append(name) }
    }

    var all: [String] {
        names.withLock { $0 }
    }
}

@Suite("Launch migrations run in order, once")
struct LaunchMigratorTests {
    private let first = SettingKey<Int>("testMigrationFirst", default: 0)
    private let second = SettingKey<Int>("testMigrationSecond", default: 0)
    private let third = SettingKey<Int>("testMigrationThird", default: 0)

    @Test("each migration starts after the one before it has finished, in the order given")
    func whenSeveral_thenOneAfterAnother() async {
        let order = Order()
        let defaults = ThrowawayDefaults.make()
        let migrations = [
            LaunchMigration(name: "a", version: first, currentVersion: 1) {
                order.add("a start")
                try? await Task.sleep(for: .milliseconds(40))
                order.add("a end")
                return .done("")
            },
            LaunchMigration(name: "b", version: second, currentVersion: 1) {
                order.add("b start")
                return .done("")
            }
        ]

        await LaunchMigrator.run(migrations, defaults: defaults)

        #expect(order.all == ["a start", "a end", "b start"])
    }

    @Test("a finished migration stores its version and is not run again")
    func whenDone_thenVersionStoredAndSkippedNextTime() async {
        let order = Order()
        let defaults = ThrowawayDefaults.make()
        let migration = LaunchMigration(name: "a", version: first, currentVersion: 3) {
            order.add("ran")
            return .done("")
        }

        let firstRun = await LaunchMigrator.run([migration], defaults: defaults)
        let secondRun = await LaunchMigrator.run([migration], defaults: defaults)

        #expect(firstRun == [.done("a")])
        #expect(secondRun == [.upToDate("a")])
        #expect(defaults.value(for: first) == 3)
        #expect(order.all == ["ran"])
    }

    @Test("an incomplete migration keeps its version, so the next launch tries again")
    func whenIncomplete_thenVersionStays() async {
        let defaults = ThrowawayDefaults.make()
        let migration = LaunchMigration(name: "a", version: first, currentVersion: 1) { .incomplete("2 kept") }

        let reports = await LaunchMigrator.run([migration], defaults: defaults)

        #expect(reports == [.incomplete("a")])
        #expect(defaults.value(for: first) == 0)
    }

    @Test("a migration that throws does not stop the ones after it, and does not store its version")
    func whenOneThrows_thenTheRestStillRun() async {
        let defaults = ThrowawayDefaults.make()
        let migrations = [
            LaunchMigration(name: "a", version: first, currentVersion: 1) { throw Failure() },
            LaunchMigration(name: "b", version: second, currentVersion: 1) { .done("") }
        ]

        let reports = await LaunchMigrator.run(migrations, defaults: defaults)

        #expect(reports == [.failed("a"), .done("b")])
        #expect(defaults.value(for: first) == 0)
        #expect(defaults.value(for: second) == 1)
    }

    @Test("a version already at or past the current one is skipped")
    func whenAlreadyCurrent_thenSkipped() async {
        let defaults = ThrowawayDefaults.make()
        defaults.set(5, for: third)

        let reports = await LaunchMigrator.run(
            [LaunchMigration(name: "c", version: third, currentVersion: 2) { .done("") }], defaults: defaults
        )

        #expect(reports == [.upToDate("c")])
    }

    @Test("the standard list is the seven migrations, in the order the data depends on, each with its own version key")
    func standardList_isDeclaredInOrder() throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrations = LaunchMigration.standard(service: StorageService(modelContainer: container))

        #expect(migrations.map(\.name) == [
            "Classifier migration", "Preview encryption", "Ciphertext binding", "Metadata sealing", "Vector sealing",
            "Clip repair", "Secret masks"
        ])
        #expect(Set(migrations.map(\.version.name)).count == migrations.count, "two migrations share a version key")
    }
}

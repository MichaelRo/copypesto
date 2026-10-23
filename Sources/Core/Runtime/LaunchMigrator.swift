// SPDX-License-Identifier: MIT
import Foundation
import os

/// One versioned job that brings data written by an older version up to date.
public struct LaunchMigration: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Finished: the stored version moves up and the job is not run again.
        case done(String)
        /// Some rows could not be converted (the key was not reachable); the version stays and the next launch tries
        /// again.
        case incomplete(String)
    }

    public let name: String
    public let version: SettingKey<Int>
    public let currentVersion: Int
    public let work: @Sendable () async throws -> Outcome

    public init(
        name: String, version: SettingKey<Int>, currentVersion: Int,
        work: @escaping @Sendable () async throws -> Outcome
    ) {
        self.name = name
        self.version = version
        self.currentVersion = currentVersion
        self.work = work
    }
}

/// Runs the declared migrations one after the other, in the order given. They used to start as six independent tasks
/// that interleaved on one storage actor, so the order the data was rewritten in depended on scheduling.
public enum LaunchMigrator {
    public enum Report: Equatable, Sendable {
        case upToDate(String)
        case done(String)
        case incomplete(String)
        case failed(String)

        public var name: String {
            switch self {
            case let .upToDate(name), let .done(name), let .incomplete(name), let .failed(name): name
            }
        }
    }

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Migrations")

    @discardableResult
    public static func run(
        _ migrations: [LaunchMigration],
        defaults: UserDefaults = AppDefaults.store
    ) async
    -> [Report] {
        var reports: [Report] = []
        for migration in migrations {
            guard defaults.value(for: migration.version) < migration.currentVersion else {
                reports.append(.upToDate(migration.name))
                continue
            }
            do {
                switch try await migration.work() {
                case let .done(summary):
                    defaults.set(migration.currentVersion, for: migration.version)
                    logger.info("\(migration.name, privacy: .public): \(summary, privacy: .public)")
                    reports.append(.done(migration.name))
                case let .incomplete(summary):
                    logger.info("\(migration.name, privacy: .public): \(summary, privacy: .public)")
                    reports.append(.incomplete(migration.name))
                }
            } catch {
                logger
                    .error(
                        "\(migration.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                    )
                reports.append(.failed(migration.name))
            }
        }
        return reports
    }
}

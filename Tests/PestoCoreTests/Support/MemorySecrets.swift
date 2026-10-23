// SPDX-License-Identifier: MIT
import Foundation
@testable import PestoCore

final class MemorySecrets: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var reads = 0

    /// How many times anything asked for a secret, to show that a screen or a timer does not hit the Keychain again.
    var readCount: Int {
        lock.withLock { reads }
    }

    func read(service: String, account: String) throws -> Data? {
        lock.withLock {
            reads += 1
            return items["\(service)|\(account)"]
        }
    }

    func write(_ data: Data, service: String, account: String) throws {
        lock.withLock { items["\(service)|\(account)"] = data }
    }

    func delete(service: String, account: String) {
        lock.withLock { _ = items.removeValue(forKey: "\(service)|\(account)") }
    }
}

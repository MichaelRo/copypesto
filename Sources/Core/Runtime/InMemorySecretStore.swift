// SPDX-License-Identifier: MIT
import Foundation

/// Secrets that live only in this process, for a UI-test launch that must not touch the Keychain.
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    public init() {}

    public func read(service: String, account: String) throws -> Data? {
        lock.withLock { items["\(service)|\(account)"] }
    }

    public func write(_ data: Data, service: String, account: String) throws {
        lock.withLock { items["\(service)|\(account)"] = data }
    }

    public func delete(service: String, account: String) {
        lock.withLock { _ = items.removeValue(forKey: "\(service)|\(account)") }
    }
}

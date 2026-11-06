// SPDX-License-Identifier: MIT
import Synchronization

/// Remembers the answer of a pure function of a string, so a card that asks on every redraw does the work once. The
/// key is the whole text, so a clip that changes asks again; a full table is emptied.
final class StringMemo<Value: Sendable>: Sendable {
    private let capacity: Int
    private let remembered = Mutex<[String: Value]>([:])

    init(capacity: Int = 4000) {
        self.capacity = capacity
    }

    func value(for text: String, compute: () -> Value) -> Value {
        if let known = remembered.withLock({ $0[text] }) { return known }
        let found = compute()
        remembered.withLock {
            if $0.count >= capacity { $0.removeAll(keepingCapacity: true) }
            $0[text] = found
        }
        return found
    }
}

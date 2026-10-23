// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// Built-in excluded apps (password managers) that the person has allowed for a while, for the day they want to copy
/// something out of one. Each allowance ends by itself, and none survives a restart of Pesto (`clear()` at launch).
public struct ExclusionAllowances {
    /// Posted when an allowance starts, is revoked or is cleared, so the watcher's rules follow at once.
    public static let didChange = Notification.Name("net.copypesto.pesto.exclusionAllowancesDidChange")

    /// Where versions before this one kept the allowances; only ever removed.
    static let legacyDefaultsKey = "temporaryExclusionAllowances"

    /// How long one allowance lasts, as chosen when it is started. The raw value is minutes; 0 is until Pesto quits.
    public enum Length: Int, CaseIterable, Sendable, Identifiable {
        case fifteenMinutes = 15
        case oneHour = 60
        case fourHours = 240
        case untilQuit = 0

        public var id: Int {
            rawValue
        }

        public var title: String {
            switch self {
            case .fifteenMinutes: "For 15 minutes"
            case .oneHour: "For 1 hour"
            case .fourHours: "For 4 hours"
            case .untilQuit: "Until Pesto quits"
            }
        }

        func end(from now: Date) -> Date {
            self == .untilQuit ? .distantFuture : now.addingTimeInterval(TimeInterval(rawValue) * 60)
        }
    }

    /// The end times, by bundle ID, in this process only. Preferences are readable and writable by any process of the
    /// same user, and an allowance never outlives a launch, so there is no reason to keep one there.
    private let store: AllowanceStore
    private let legacyDefaults: UserDefaults

    public init(store: AllowanceStore = .process, legacyDefaults: UserDefaults = AppDefaults.store) {
        self.store = store
        self.legacyDefaults = legacyDefaults
    }

    /// The allowances still running, as bundle ID to end time.
    public func active(now: Date = .now) -> [String: Date] {
        store.active(now: now)
    }

    @discardableResult
    public func allow(_ bundleID: String, length: Length = .oneHour, now: Date = .now) -> Date {
        let end = length.end(from: now)
        store.set(end, for: bundleID, now: now)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return end
    }

    public func revoke(_ bundleID: String, now: Date = .now) {
        store.set(nil, for: bundleID, now: now)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// The apps whose allowance was running in `previous` and is gone in `current`, because it ran out or was revoked.
    /// An allowance that merely changed its end is not ended.
    public static func ended(from previous: [String: Date], to current: [String: Date]) -> Set<String> {
        Set(previous.keys).subtracting(current.keys)
    }

    /// Called at launch: empties the store and removes the key earlier versions kept the allowances under.
    public func clear() {
        store.removeAll()
        legacyDefaults.removeObject(forKey: Self.legacyDefaultsKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// The running allowances of one process.
public final class AllowanceStore: Sendable {
    public static let process = AllowanceStore()

    private let ends = Mutex<[String: Date]>([:])

    public init() {}

    func active(now: Date) -> [String: Date] {
        ends.withLock { stored in
            stored = stored.filter { $0.value > now }
            return stored
        }
    }

    func set(_ end: Date?, for bundleID: String, now: Date) {
        ends.withLock { stored in
            stored = stored.filter { $0.value > now }
            stored[bundleID] = end
        }
    }

    func removeAll() {
        ends.withLock { $0 = [:] }
    }
}

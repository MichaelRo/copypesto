// SPDX-License-Identifier: MIT
import Foundation

/// When an automatic backup runs: a few minutes after the last change, so a burst of copying makes one file, and never
/// more than once an hour, so a busy day does not rewrite a large file all day.
public enum AutoBackupPolicy {
    public static let settleDelay: TimeInterval = 300
    public static let minimumInterval: TimeInterval = 3600

    /// Seconds to wait before the next backup, or nil when nothing has changed since the last one.
    public static func delay(lastChange: Date?, lastBackup: Date?, now: Date) -> TimeInterval? {
        guard let lastChange else { return nil }
        if let lastBackup, lastChange <= lastBackup { return nil }
        let settled = max(0, lastChange.addingTimeInterval(settleDelay).timeIntervalSince(now))
        let spaced = lastBackup.map { max(0, $0.addingTimeInterval(minimumInterval).timeIntervalSince(now)) } ?? 0
        return max(settled, spaced)
    }

    public static func nextBackup(lastChange: Date?, lastBackup: Date?, now: Date) -> Date? {
        delay(lastChange: lastChange, lastBackup: lastBackup, now: now).map { now.addingTimeInterval($0) }
    }
}

/// What the person chose for automatic backup, kept per Mac in the preferences. None of it is part of the settings file
/// Pesto exports, so a work Mac never inherits a home Mac's folder or switch.
public struct AutoBackupSettings {
    public static let enabledKey = "autoBackupEnabled"
    public static let folderKey = "autoBackupFolder"
    public static let headerKey = "autoBackupHeader"
    public static let lastBackupKey = "autoBackupLastDate"
    public static let lastBytesKey = "autoBackupLastBytes"
    public static let includeSecretsKey = "autoBackupIncludesSecrets"
    public static let lastSkippedLargeKey = "autoBackupSkippedLarge"
    public static let lastClipCountKey = "autoBackupLastClipCount"
    public static let pausedAfterClearKey = "autoBackupPausedAfterClear"
    public static let automaticKey = "autoBackupRunsAutomatically"
    public static let protectionKey = "autoBackupProtection"
    public static let problemKey = "autoBackupProblem"
    public static let largestClipBytes = 10 * 1024 * 1024

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppDefaults.store) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    public var folder: URL? {
        get { defaults.string(forKey: Self.folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        nonmutating set { defaults.set(newValue?.path, forKey: Self.folderKey) }
    }

    /// The header of the last backup written, which later ones reuse so no passphrase is asked for again.
    public var header: Data? {
        get { defaults.data(forKey: Self.headerKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.headerKey) }
    }

    public var lastBackup: Date? {
        get { defaults.object(forKey: Self.lastBackupKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.lastBackupKey) }
    }

    public var lastBytes: Int {
        get { defaults.integer(forKey: Self.lastBytesKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.lastBytesKey) }
    }

    /// How many clips the last backup held, for refusing a backup that is suddenly far smaller. Nil after Clear
    /// Everything, because that is the person's own doing.
    public var lastClipCount: Int? {
        get { defaults.object(forKey: Self.lastClipCountKey) as? Int }
        nonmutating set { defaults.set(newValue, forKey: Self.lastClipCountKey) }
    }

    /// Clips left on purpose (the retention policy expiring them, or the person clearing a range after confirming)
    /// are not a history that went missing, so the next backup is judged against what is left. A shrink nobody asked
    /// for is still caught: it is not reported here.
    public func lowerBaseline(by removed: Int) {
        guard removed > 0, let baseline = lastClipCount else { return }
        lastClipCount = max(0, baseline - removed)
    }

    /// Set when the person cleared everything and chose to keep the backup: automatic backup leaves the file alone
    /// until
    /// they confirm a new one with Back Up Now.
    /// What the last run could not do, kept so a pane can say "Needs you" without opening the Keychain or waiting for
    /// the next run. Nil after a backup is written.
    public var problem: BackupProblem? {
        get { defaults.string(forKey: Self.problemKey).flatMap(BackupProblem.init(rawValue:)) }
        nonmutating set {
            if let newValue { defaults.set(newValue.rawValue, forKey: Self.problemKey) } else {
                defaults.removeObject(forKey: Self.problemKey)
            }
        }
    }

    public var pausedAfterClear: Bool {
        get { defaults.bool(forKey: Self.pausedAfterClearKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.pausedAfterClearKey) }
    }

    public var lastSkippedLarge: Int {
        get { defaults.integer(forKey: Self.lastSkippedLargeKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.lastSkippedLargeKey) }
    }

    /// Whether the backup keeps itself up to date. A backup that has been set up does, unless the person says not to;
    /// then it is written only when they ask (Back Up Now).
    public var runsAutomatically: Bool {
        get { defaults.object(forKey: Self.automaticKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.automaticKey) }
    }

    public enum Protection: String, Sendable {
        case passphrase
        case recoveryKey
    }

    /// What the person chose to protect the file with, for showing in Settings.
    public var protection: Protection? {
        get { defaults.string(forKey: Self.protectionKey).flatMap(Protection.init(rawValue:)) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: Self.protectionKey) }
    }

    public var includesSecrets: Bool {
        get { defaults.bool(forKey: Self.includeSecretsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.includeSecretsKey) }
    }

    /// A folder named Pesto in iCloud Drive, when this Mac has iCloud Drive turned on; the suggested place for the
    /// file.
    public static func iCloudDriveFolder(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    )
    -> URL? {
        let drive = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Pesto", isDirectory: true)
    }

    /// One file per Mac, named for it and for its device id, so two Macs that share a folder never overwrite each
    /// other even when they have the same name.
    public static func fileName(forMac name: String, deviceID: String) -> String {
        let fragment = String(deviceID.filter { $0.isLetter || $0.isNumber }.prefix(8))
        guard !fragment.isEmpty else { return legacyFileName(forMac: name) }
        return "Pesto Backup \u{2013} \(safeMacName(name)) (\(fragment)).pestobackup"
    }

    /// The name used before the device id was added; a file under it is adopted when it carries this Mac's header.
    public static func legacyFileName(forMac name: String) -> String {
        "Pesto Backup \u{2013} \(safeMacName(name)).pestobackup"
    }

    private static func safeMacName(_ name: String) -> String {
        let safe = name.map { "/:\\".contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "Mac" : safe
    }

    /// Switches it off and forgets the folder and header; the Keychain key stays so manual backups keep their recovery
    /// key.
    public func turnOff() {
        isEnabled = false
        header = nil
        defaults.removeObject(forKey: Self.automaticKey)
        defaults.removeObject(forKey: Self.protectionKey)
        defaults.removeObject(forKey: Self.lastClipCountKey)
        defaults.removeObject(forKey: Self.pausedAfterClearKey)
        defaults.removeObject(forKey: Self.problemKey)
    }
}

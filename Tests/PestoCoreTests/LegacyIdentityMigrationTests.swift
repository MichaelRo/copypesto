// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

private final class FakeSecrets: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    var failReads = false

    private func id(_ service: String, _ account: String) -> String {
        "\(service)|\(account)"
    }

    func read(service: String, account: String) throws -> Data? {
        if failReads { throw KeychainSecretStore.Failure(status: -25_293) }
        return lock.withLock { items[id(service, account)] }
    }

    func write(_ data: Data, service: String, account: String) throws {
        lock.withLock { items[id(service, account)] = data }
    }

    func delete(service: String, account: String) {
        lock.withLock { _ = items.removeValue(forKey: id(service, account)) }
    }

    func has(_ service: String, _ account: String) -> Bool {
        lock.withLock { items[id(service, account)] != nil }
    }
}

/// Every preferences domain here is a throwaway name. The real `io.pesto.app` domain is a user's actual settings:
/// a test must never read, write or remove it.
@Suite("Moving an install from the old bundle ID")
final class LegacyIdentityMigrationTests {
    private let root: URL
    private let legacyDefaults: UserDefaults
    private let currentDefaults: UserDefaults
    private let secrets = FakeSecrets()
    private let tag = UUID().uuidString
    private var legacyName: String {
        ThrowawayDefaults.domain("legacy-defaults-\(tag)")
    }

    private var currentName: String {
        ThrowawayDefaults.domain("current-defaults-\(tag)")
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        legacyDefaults = ThrowawayDefaults.make("legacy-defaults-\(tag)")
        currentDefaults = ThrowawayDefaults.make("current-defaults-\(tag)")
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private var legacyDirectory: URL {
        root.appendingPathComponent(AppIdentity.legacySupportDirectoryName)
    }

    private var currentDirectory: URL {
        root.appendingPathComponent(AppIdentity.supportDirectoryName)
    }

    private func migration() -> LegacyIdentityMigration {
        LegacyIdentityMigration(
            applicationSupport: root, legacyDefaults: legacyDefaults, legacyDomain: legacyName,
            currentDefaults: currentDefaults, secrets: secrets
        )
    }

    private func makeLegacyStore(contents: String = "clips") throws {
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: legacyDirectory.appendingPathComponent("clips.store"))
    }

    private func seedLegacyKey(_ bytes: String = "key-bytes") throws {
        try secrets.write(
            Data(bytes.utf8), service: AppIdentity.legacyKeychainService, account: AppIdentity.legacyBlobKeyAccount
        )
    }

    @Test("a fresh install has nothing to move and creates nothing")
    func whenNoLegacyInstall_thenNothing() {
        let report = migration().run()

        #expect(report == .init(store: .nothingToMove, preferencesCopied: 0, key: .nothingToMove))
        #expect(!FileManager.default.fileExists(atPath: currentDirectory.path))
    }

    @Test("the data folder moves whole, with its contents")
    func whenLegacyFolder_thenMoved() throws {
        try makeLegacyStore(contents: "history")

        let report = migration().run()

        #expect(report.store == .moved)
        #expect(!FileManager.default.fileExists(atPath: legacyDirectory.path))
        let moved = try String(contentsOf: currentDirectory.appendingPathComponent("clips.store"), encoding: .utf8)
        #expect(moved == "history")
    }

    @Test("an empty new folder does not block the move")
    func whenCurrentFolderEmpty_thenStillMoved() throws {
        try makeLegacyStore()
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)

        #expect(migration().run().store == .moved)
        #expect(FileManager.default.fileExists(atPath: currentDirectory.appendingPathComponent("clips.store").path))
    }

    @Test("a new folder that already holds data is never overwritten")
    func whenBothFoldersHoldData_thenConflictAndNothingLost() throws {
        try makeLegacyStore(contents: "old")
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: currentDirectory.appendingPathComponent("clips.store"))
        try seedLegacyKey()

        let report = migration().run()

        #expect(report.store == .conflict)
        #expect(FileManager.default.fileExists(atPath: legacyDirectory.appendingPathComponent("clips.store").path))
        #expect(try String(contentsOf: currentDirectory.appendingPathComponent("clips.store"), encoding: .utf8) ==
            "new")
        #expect(report.key == .movedKeepingOld)
        #expect(secrets.has(AppIdentity.legacyKeychainService, AppIdentity.legacyBlobKeyAccount), "old key kept")
    }

    @Test("settings are copied once, without system keys, and never over a current install")
    func whenPreferences_thenCopiedOnce() {
        legacyDefaults.setPersistentDomain(
            ["hasOnboarded": true, "cardSize": "compact", "NSWindow Frame x": "1", "AppleLanguages": ["en"]],
            forName: legacyName
        )

        let first = migration().run()
        currentDefaults.set("standard", forKey: "cardSize")
        let second = migration().run()

        #expect(first.preferencesCopied == 2)
        #expect(currentDefaults.bool(forKey: "hasOnboarded"))
        #expect(currentDefaults.object(forKey: "NSWindow Frame x") == nil)
        #expect(second.preferencesCopied == 0)
        #expect(currentDefaults.string(forKey: "cardSize") == "standard", "a second run must not revert settings")
    }

    @Test("resetting the onboarding flag does not bring the old preferences back")
    func whenOnboardingFlagIsReset_thenTheOldDomainIsNotCopiedAgain() {
        legacyDefaults.setPersistentDomain(["hasOnboarded": true, "cardSize": "compact"], forName: legacyName)
        migration().run()
        currentDefaults.removeObject(forKey: "hasOnboarded")

        let again = migration().run()

        #expect(again.preferencesCopied == 0)
        #expect(currentDefaults.object(forKey: "hasOnboarded") == nil, "a reset must stay reset")
    }

    @Test("a Mac that already has its own onboarding flag is never given the old preferences")
    func whenCurrentInstallHasItsOwnFlag_thenNothingCopiedAndMarkerSet() {
        legacyDefaults.setPersistentDomain(["cardSize": "compact"], forName: legacyName)
        currentDefaults.set(true, forKey: "hasOnboarded")

        let report = migration().run()

        #expect(report.preferencesCopied == 0)
        currentDefaults.removeObject(forKey: "hasOnboarded")
        #expect(migration().run().preferencesCopied == 0)
    }

    @Test("the key is copied, checked, and the old one deleted once the folder has moved")
    func whenKeyAndFolder_thenKeyMovedAndOldDeleted() throws {
        try makeLegacyStore()
        try seedLegacyKey("secret")

        let report = migration().run()

        #expect(report.key == .moved)
        #expect(try secrets
            .read(service: AppIdentity.keychainService, account: AppIdentity.blobKeyAccount) == Data("secret".utf8))
        #expect(!secrets.has(AppIdentity.legacyKeychainService, AppIdentity.legacyBlobKeyAccount))
    }

    @Test("a key that is already current is left alone, and running twice changes nothing")
    func whenRunTwice_thenSecondIsANoOp() throws {
        try makeLegacyStore()
        try seedLegacyKey("secret")
        migration().run()

        let again = migration().run()

        #expect(again == .init(store: .nothingToMove, preferencesCopied: 0, key: .alreadyCurrent))
    }

    @Test("if the Keychain refuses the read, nothing is deleted and the next launch can try again")
    func whenKeychainDenied_thenFailedAndRetryable() throws {
        try makeLegacyStore()
        try seedLegacyKey("secret")
        secrets.failReads = true

        let first = migration().run()
        secrets.failReads = false
        #expect(first.key == .failed)
        #expect(first.store == .moved)
        #expect(secrets.has(AppIdentity.legacyKeychainService, AppIdentity.legacyBlobKeyAccount))
        #expect(migration().run().key == .moved, "the folder is already moved, so the old key may go now")
    }
}

@Suite("Keychain secret store")
struct KeychainSecretStoreTests {
    @Test("a secret can be written, read back and deleted, and a missing one reads as nil")
    func whenWrittenThenRead_thenRoundTrips() throws {
        let store = KeychainSecretStore()
        let service = "io.pesto.tests.secret-store.\(UUID().uuidString)"
        defer { store.delete(service: service, account: "a") }

        #expect(try store.read(service: service, account: "a") == nil)
        try store.write(Data("one".utf8), service: service, account: "a")
        #expect(try store.read(service: service, account: "a") == Data("one".utf8))
        store.delete(service: service, account: "a")
        #expect(try store.read(service: service, account: "a") == nil)
    }
}

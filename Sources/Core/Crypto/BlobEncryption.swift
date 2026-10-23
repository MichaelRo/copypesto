// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Security
import Synchronization

/// AES-GCM-256 envelope for `ClipboardBlob` payloads. See ADR 0002.
///
/// The symmetric key is generated once per install and stored in the Keychain.
/// The key is not wrapped by the Secure Enclave (ADR 0002). The Keychain item is created with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
///
/// On a fresh install: the first call to `loadOrCreateKey()` generates a new key.
/// On subsequent launches: the same key is loaded. If the user signs into a different
/// Apple ID, the Keychain item won't transfer and all blobs become unrecoverable —
/// this is documented in the privacy settings pane.
public struct BlobEncryption: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case keychainAccessFailed(OSStatus)
        case decryptionFailed
        case invalidNonce
        case keyMissing
    }

    public struct EncryptedEnvelope: Sendable, Equatable {
        public let ciphertext: Data
        public let nonce: Data

        public init(ciphertext: Data, nonce: Data) {
            self.ciphertext = ciphertext
            self.nonce = nonce
        }
    }

    public let keychainService: String
    public let keychainAccount: String

    public init(
        keychainService: String = AppIdentity.keychainService,
        keychainAccount: String = AppIdentity.blobKeyAccount
    ) {
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }

    public enum Field: String, Sendable {
        case blob
        case preview
        case metadata
        case embedding
    }

    /// What a ciphertext is bound to: the item it belongs to and which of its fields it is, so a ciphertext moved to
    /// another row, or from one field to another, no longer opens.
    public static func associatedData(itemID: UUID, field: Field) -> Data {
        Data("pesto.v2|\(itemID.uuidString)|\(field.rawValue)".utf8)
    }

    public func encrypt(_ plaintext: Data, associatedData: Data? = nil) throws -> EncryptedEnvelope {
        let key = try loadOrCreateKey()
        let sealed = try Self.seal(plaintext, using: key, associatedData: associatedData)
        // The combined representation contains nonce + ciphertext + tag. We split for storage:
        // store the nonce separately, the ciphertext + tag together (so the on-disk size
        // is plaintext.size + 16 byte tag).
        let nonceBytes = sealed.nonce.withUnsafeBytes { Data($0) }
        // Normalize to startIndex=0: sealed.ciphertext and .tag are slices of CryptoKit's
        // internal combined buffer (startIndex == nonceLength). Without normalization,
        // the resulting Data has a non-zero startIndex that causes subscript traps on macOS 26.
        let cipherAndTag = Data(sealed.ciphertext) + Data(sealed.tag)
        return EncryptedEnvelope(ciphertext: cipherAndTag, nonce: nonceBytes)
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey, associatedData: Data?) throws -> AES.GCM.SealedBox {
        guard let associatedData else { return try AES.GCM.seal(plaintext, using: key) }
        return try AES.GCM.seal(plaintext, using: key, authenticating: Data(associatedData))
    }

    static func open(_ sealed: AES.GCM.SealedBox, using key: SymmetricKey, associatedData: Data?) throws -> Data {
        guard let associatedData else { return try AES.GCM.open(sealed, using: key) }
        return try AES.GCM.open(sealed, using: key, authenticating: Data(associatedData))
    }

    public func decrypt(_ envelope: EncryptedEnvelope, associatedData: Data? = nil) throws -> Data {
        let key = try loadOrCreateKey()
        guard let nonce = try? AES.GCM.Nonce(data: envelope.nonce) else {
            throw Error.invalidNonce
        }
        // Reverse the split done in encrypt(): last 16 bytes are the tag.
        guard envelope.ciphertext.count >= 16 else { throw Error.decryptionFailed }
        let tag = envelope.ciphertext.suffix(16)
        let cipher = envelope.ciphertext.prefix(envelope.ciphertext.count - 16)
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipher, tag: tag)
        do {
            return try Self.open(sealed, using: key, associatedData: associatedData)
        } catch {
            throw Error.decryptionFailed
        }
    }

    /// Test-only convenience: use a deterministic key. Production code should never call this.
    public static func ephemeral() -> (BlobEncryption, SymmetricKey) {
        let key = SymmetricKey(size: .bits256)
        return (BlobEncryption(keychainService: UUID().uuidString, keychainAccount: UUID().uuidString), key)
    }

    // MARK: - Keychain

    /// Whether the encryption key is in the Keychain, without creating one. A Keychain that cannot answer (locked,
    /// interaction not allowed) is `.unavailable`, never `.absent`: only "item not found" means the key is gone.
    public static func keyPresence(
        service: String = AppIdentity.keychainService,
        account: String = AppIdentity.blobKeyAccount
    )
    -> KeyPresence {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return KeyPresence(status: SecItemCopyMatching(query as CFDictionary, nil))
    }

    public static func keyExists(
        service: String = AppIdentity.keychainService,
        account: String = AppIdentity.blobKeyAccount
    )
    -> Bool {
        keyPresence(service: service, account: account) == .present
    }

    /// Stores a freshly made key. When an item already exists (a second process, or an item `loadKey` could not
    /// read), the stored key is the one in use, never the new one, which no future launch could find.
    static func mintOrAdopt(
        newKey: SymmetricKey,
        add: (Data) -> OSStatus,
        load: () throws -> Data?
    ) throws
    -> SymmetricKey {
        let status = add(newKey.withUnsafeBytes { Data($0) })
        switch status {
        case errSecSuccess:
            return newKey
        case errSecDuplicateItem:
            guard let stored = try load() else { throw Error.keychainAccessFailed(status) }
            return SymmetricKey(data: stored)
        default:
            throw Error.keychainAccessFailed(status)
        }
    }

    /// A key derived from the test session, or nil in a normal launch. Deterministic per session so
    /// data written before an app relaunch can still be decrypted; never stored in the Keychain.
    static func isolatedKey(for configuration: RuntimeConfiguration) -> SymmetricKey? {
        guard configuration.mode != .normal else { return nil }
        let digest = SHA256.hash(data: Data("io.pesto.isolated-key.\(configuration.session)".utf8))
        return SymmetricKey(data: Data(digest))
    }

    /// True when a usable key exists: the in-memory test key, or the Keychain item in a normal launch.
    public static var isKeyAvailable: Bool {
        isolatedKey(for: RuntimeConfiguration.current) != nil || keyExists()
    }

    public enum KeyResolution: Equatable {
        case use(SymmetricKey)
        case mint
    }

    /// While locked, a missing key is an error rather than a cue to mint a new one: the data it
    /// protected would silently become unreadable.
    public static func resolve(existing: SymmetricKey?, mintingLocked: Bool) throws -> KeyResolution {
        if let existing { return .use(existing) }
        if mintingLocked { throw Error.keyMissing }
        return .mint
    }

    public static func setMintingLocked(_ locked: Bool) {
        keyState.withLock { $0.mintingLocked = locked }
    }

    /// The key as loaded once for this process, and whether a missing key may be minted. One lock holds both, and it is
    /// held across the Keychain read, so a second caller waits for the first instead of reading the Keychain again.
    private struct KeyState {
        var cached: SymmetricKey?
        var mintingLocked = false
    }

    private static let keyState = Mutex(KeyState())

    public func loadOrCreateKey() throws -> SymmetricKey {
        if let isolated = Self.isolatedKey(for: RuntimeConfiguration.current) { return isolated }
        // Cache the key in memory for the process lifetime. macOS Keychain ACLs
        // are tied to the creating process's code signature, so on dev builds
        // where the CDHash changes between launches every Keychain access can
        // re-prompt. Even within a single launch, without this cache every
        // encrypt/decrypt call would round-trip through SecItemCopyMatching and
        // any prompt the user hasn't "Always Allowed" would re-appear.
        return try Self.keyState.withLock { state in
            if let cached = state.cached { return cached }
            let key: SymmetricKey = switch try Self.resolve(existing: loadKey(), mintingLocked: state.mintingLocked) {
            case let .use(existing):
                existing
            case .mint:
                try Self.mintOrAdopt(
                    newKey: SymmetricKey(size: .bits256),
                    add: { addKeyItem($0) },
                    load: { try loadKey().map { $0.withUnsafeBytes { Data($0) } } }
                )
            }
            state.cached = key
            return key
        }
    }

    /// Replaces the install key with a new random one, in place (the Keychain item keeps its access list), and uses it
    /// from
    /// now on. Everything sealed under the old key can no longer be opened, which is the point: Clear Everything
    /// deletes the
    /// rows, but SQLite leaves their bytes in freed pages and the write-ahead log until they are reused, so the only
    /// way to
    /// make those bytes unreadable is to change the key. A test or UI-test launch keeps its fixed session key.
    public func rotateKey() throws {
        if Self.isolatedKey(for: RuntimeConfiguration.current) != nil { return }
        try Self.keyState.withLock { state in
            state.cached = try Self.replaceKey(
                newKey: SymmetricKey(size: .bits256),
                update: { updateKeyItem($0) },
                add: { addKeyItem($0) }
            )
        }
    }

    /// Stores `newKey` over the existing item, or adds it when there is none (a Keychain that lost the item between the
    /// delete and the clear), and returns it only once the Keychain has it, so memory never holds a key no launch can
    /// find.
    static func replaceKey(
        newKey: SymmetricKey,
        update: (Data) -> OSStatus,
        add: (Data) -> OSStatus
    ) throws
    -> SymmetricKey {
        let data = newKey.withUnsafeBytes { Data($0) }
        var status = update(data)
        if status == errSecItemNotFound { status = add(data) }
        guard status == errSecSuccess else { throw Error.keychainAccessFailed(status) }
        return newKey
    }

    private func updateKeyItem(_ data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    }

    private func loadKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw Error.keychainAccessFailed(status)
        }
    }

    private func addKeyItem(_ data: Data) -> OSStatus {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(attrs as CFDictionary, nil)
    }
}

/// Test-friendly variant that takes the key explicitly. Production code uses `BlobEncryption`.
public struct BlobEncryptionWithKey: Sendable {
    public let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public func encrypt(_ plaintext: Data, associatedData: Data? = nil) throws -> BlobEncryption.EncryptedEnvelope {
        let sealed = try BlobEncryption.seal(plaintext, using: key, associatedData: associatedData)
        let nonceBytes = sealed.nonce.withUnsafeBytes { Data($0) }
        return BlobEncryption.EncryptedEnvelope(
            ciphertext: Data(sealed.ciphertext) + Data(sealed.tag),
            nonce: nonceBytes
        )
    }

    public func decrypt(_ envelope: BlobEncryption.EncryptedEnvelope, associatedData: Data? = nil) throws -> Data {
        guard let nonce = try? AES.GCM.Nonce(data: envelope.nonce) else {
            throw BlobEncryption.Error.invalidNonce
        }
        guard envelope.ciphertext.count >= 16 else { throw BlobEncryption.Error.decryptionFailed }
        let tag = envelope.ciphertext.suffix(16)
        let cipher = envelope.ciphertext.prefix(envelope.ciphertext.count - 16)
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipher, tag: tag)
        do {
            return try BlobEncryption.open(sealed, using: key, associatedData: associatedData)
        } catch {
            throw BlobEncryption.Error.decryptionFailed
        }
    }
}

public enum KeyPresence: Equatable, Sendable {
    case present
    case absent
    case unavailable(OSStatus)

    public init(status: OSStatus) {
        switch status {
        case errSecSuccess: self = .present
        case errSecItemNotFound: self = .absent
        default: self = .unavailable(status)
        }
    }
}

public enum KeyStartupDecision: Equatable, Sendable {
    case ready
    case freshInstall
    case keyMissingWithExistingData
    case keychainUnavailable
    case keyDoesNotOpenHistory

    /// `canaryOpens` is whether a few stored rows decrypted under the key; nil when it was not tried.
    public static func evaluate(
        presence: KeyPresence,
        encryptedRowCount: Int,
        canaryOpens: Bool? = nil
    )
    -> KeyStartupDecision {
        switch presence {
        case .unavailable:
            .keychainUnavailable
        case .present:
            canaryOpens == false && encryptedRowCount > 0 ? .keyDoesNotOpenHistory : .ready
        case .absent:
            encryptedRowCount > 0 ? .keyMissingWithExistingData : .freshInstall
        }
    }
}

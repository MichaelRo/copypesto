// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// How a clip's content fingerprint is stored. The watcher still computes a plain SHA-256 of the payload, but a plain
/// hash is stored nowhere: it would let anyone holding the store file test guesses (a Social Security number has about
/// a billion values). What is stored is `HMAC(key, plain hash)` under a key derived from the install's encryption key,
/// tagged `h2:`, so duplicates are still found and nothing about the content can be checked without the key.
public enum ContentHash {
    public static let prefix = "h2:"

    public static func isKeyed(_ stored: String) -> Bool {
        stored.hasPrefix(prefix)
    }

    /// The form to store for a plain hash. Without a key (before the encryption key exists) the plain hash is kept
    /// and the launch migration upgrades it later.
    public static func stored(_ plain: String, key: SymmetricKey?) -> String {
        guard !isKeyed(plain), let key else { return plain }
        let mac = HMAC<SHA256>.authenticationCode(for: Data(plain.utf8), using: derived(from: key))
        return prefix + mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Every form the same content may be stored under, newest first: a lookup for a duplicate tries them all.
    public static func candidates(for plain: String, key: SymmetricKey?) -> [String] {
        let keyed = stored(plain, key: key)
        return keyed == plain ? [plain] : [keyed, plain]
    }

    /// The keyed form of a legacy stored hash, or nil when it is already keyed (or there is no key).
    public static func migrated(legacy: String, key: SymmetricKey?) -> String? {
        guard !isKeyed(legacy), key != nil else { return nil }
        return stored(legacy, key: key)
    }

    private static func derived(from key: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            info: Data("io.pesto.content-hash.v1".utf8),
            outputByteCount: 32
        )
    }
}

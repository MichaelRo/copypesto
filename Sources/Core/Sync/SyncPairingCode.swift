// SPDX-License-Identifier: MIT
import CommonCrypto
import CryptoKit
import Foundation

/// Eight words both Macs show while one approves the other's join (interim mode, ADR 0018, ADR 0039). They are derived
/// from both public keys and the vault, so a provider that swaps a key shows the two Macs different words. Eighty bits,
/// stretched with PBKDF2, so a provider that grinds key pairs on both sides until the two screens match (a birthday
/// search) pays for a slow derivation on every guess and needs about 2^40 of them.
public enum SyncPairingCode {
    public static let wordCount = 8
    public static let stretchIterations = 600_000

    public static func words(vaultID: Data, keyA: Data, keyB: Data) -> [String] {
        let ordered = [keyA, keyB].sorted { $0.lexicographicallyPrecedes($1) }
        var hash = SHA256()
        hash.update(data: Data("pesto-pair-v1".utf8))
        hash.update(data: vaultID)
        for key in ordered {
            hash.update(data: key)
        }
        var bits = stretched(Data(hash.finalize())).reduce(UInt128(0)) { $0 << 8 | UInt128($1) }
        var out: [String] = []
        for _ in 0..<wordCount {
            out.append(SyncWordList.words[Int(bits & 1023)])
            bits >>= 10
        }
        return out
    }

    private static func stretched(_ digest: Data) -> [UInt8] {
        var derived = [UInt8](repeating: 0, count: wordCount * 10 / 8)
        let salt = Array("pesto-pair-v2".utf8)
        let status = digest.withUnsafeBytes { seed in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                seed.bindMemory(to: Int8.self).baseAddress, digest.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(stretchIterations),
                &derived, derived.count
            )
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return derived
    }

    public static func display(vaultID: Data, keyA: Data, keyB: Data) -> String {
        words(vaultID: vaultID, keyA: keyA, keyB: keyB).joined(separator: " ")
    }
}

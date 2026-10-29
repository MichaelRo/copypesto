// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// Six words both Macs show while one approves the other's join (interim mode, ADR 0018). They are derived from both
/// public keys and the vault, so a provider that swaps a key shows the two Macs different words.
public enum SyncPairingCode {
    public static let wordCount = 6

    public static func words(vaultID: Data, keyA: Data, keyB: Data) -> [String] {
        let ordered = [keyA, keyB].sorted { $0.lexicographicallyPrecedes($1) }
        var hash = SHA256()
        hash.update(data: Data("pesto-pair-v1".utf8))
        hash.update(data: vaultID)
        for key in ordered {
            hash.update(data: key)
        }
        let digest = Array(hash.finalize())
        var bits = digest.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        var out: [String] = []
        for _ in 0..<wordCount {
            out.append(SyncWordList.words[Int(bits & 1023)])
            bits >>= 10
        }
        return out
    }

    public static func display(vaultID: Data, keyA: Data, keyB: Data) -> String {
        words(vaultID: vaultID, keyA: keyA, keyB: keyB).joined(separator: " ")
    }
}

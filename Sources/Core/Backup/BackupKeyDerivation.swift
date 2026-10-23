// SPDX-License-Identifier: MIT
import CommonCrypto
import CryptoKit
import Foundation

public enum BackupKeyDerivation {
    public static let defaultIterations = 600_000
    static let maximumIterations = 10_000_000

    static func pbkdf2SHA256(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey? {
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passphrase, passphrase.utf8.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: derived)
    }
}

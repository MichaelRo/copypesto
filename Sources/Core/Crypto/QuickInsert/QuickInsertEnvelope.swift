// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// The quick-insert file (ADR 0051): `PESTOQIS`, a version byte, then the set sealed under the shared quick-insert key
/// (`SealedFileEnvelope` in the `.quickInsert` format).
public enum QuickInsertEnvelope {
    public static func seal(_ set: QuickInsertSet, with key: SymmetricKey) throws -> Data {
        try SealedFileEnvelope.seal(set, as: .quickInsert, with: key)
    }

    public static func open(_ data: Data, with key: SymmetricKey) throws -> QuickInsertSet {
        try SealedFileEnvelope.open(QuickInsertSet.self, from: data, as: .quickInsert, with: key)
    }
}

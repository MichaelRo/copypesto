// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import os
import PestoCore
import Synchronization

/// Opens the snapshot the app wrote (ADR 0052) with the key of the Keychain group only the app and the widget hold,
/// caching the decoded snapshot keyed by file stamp and key digest so page flips redraw without decrypting or
/// decoding JSON again. Any missing file, missing key, or read failure clears the cache and returns nil.
enum WidgetSnapshotReader {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Widget")

    private struct FileStamp: Equatable {
        let modifiedAt: Date
        let byteCount: Int64
    }

    private struct CachedSnapshot {
        let url: URL
        let stamp: FileStamp
        let account: String
        let keyDigest: Data
        let snapshot: WidgetSnapshot
    }

    private static let cache = Mutex<CachedSnapshot?>(nil)

    static func read() -> WidgetSnapshot? {
        guard let file = SealedGroupFile.current(.widgetSnapshot), let group = WidgetSharing.keychainGroup() else {
            return nil
        }
        let keys = SharedFileKeyStore(
            secrets: SharedKeychainSecretStore(accessGroup: group), account: AppIdentity.widgetKeyAccount
        )
        return read(file: file, keys: keys)
    }

    static func read(file: SealedGroupFile, keys: SharedFileKeyStore) -> WidgetSnapshot? {
        guard let initialStamp = fileStamp(at: file.url) else {
            invalidateCache(for: file.url)
            return nil
        }
        do {
            guard let key = try keys.key() else {
                invalidateCache(for: file.url)
                return nil
            }
            let digest = keyDigest(for: key)
            if let hit = cache.withLock({ $0 }),
               hit.url == file.url,
               hit.stamp == initialStamp,
               hit.account == keys.account,
               hit.keyDigest == digest
            {
                return hit.snapshot
            }
            let snapshot = try file.read(WidgetSnapshot.self, with: key)
            let finalStamp = fileStamp(at: file.url) ?? initialStamp
            cache.withLock {
                $0 = CachedSnapshot(
                    url: file.url, stamp: finalStamp, account: keys.account, keyDigest: digest, snapshot: snapshot
                )
            }
            return snapshot
        } catch SealedFileError.missing {
            invalidateCache(for: file.url)
            return nil
        } catch {
            invalidateCache(for: file.url)
            logger.error("The widget snapshot did not open: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    static func clearCache() {
        cache.withLock { $0 = nil }
    }

    private static func invalidateCache(for url: URL) {
        cache.withLock {
            if $0?.url == url { $0 = nil }
        }
    }

    private static func keyDigest(for key: SymmetricKey) -> Data {
        key.withUnsafeBytes { bytes in
            Data(SHA256.hash(data: bytes))
        }
    }

    private static func fileStamp(at url: URL) -> FileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber else { return nil }
        return FileStamp(modifiedAt: modifiedAt, byteCount: size.int64Value)
    }
}

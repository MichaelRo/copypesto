// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

/// Opens the snapshot the app wrote (ADR 0052) with the key of the Keychain group only the app and the widget hold,
/// on every timeline request. It never opens the store and keeps nothing between requests: any failure is nil, which
/// the widget draws as "Open Pesto to show your clips".
enum WidgetSnapshotReader {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Widget")

    static func read() -> WidgetSnapshot? {
        guard let file = SealedGroupFile.current(.widgetSnapshot) else { return nil }
        let keys = SharedFileKeyStore(
            secrets: SharedKeychainSecretStore(accessGroup: AppIdentity.widgetKeychainGroup(in: .main)),
            account: AppIdentity.widgetKeyAccount
        )
        return read(file: file, keys: keys)
    }

    static func read(file: SealedGroupFile, keys: SharedFileKeyStore) -> WidgetSnapshot? {
        do {
            guard let key = try keys.key() else { return nil }
            return try file.read(WidgetSnapshot.self, with: key)
        } catch SealedFileError.missing {
            return nil
        } catch {
            logger.error("The widget snapshot did not open: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

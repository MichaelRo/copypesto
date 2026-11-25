// SPDX-License-Identifier: MIT
import Foundation
import os

private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "SyncFolderService")

/// The app catalog each device writes and the others read (ADR 0068), kept off an idle pass.
extension SyncFolderService {
    /// Writes this device's app catalog when its list changed (ADR 0068). A failure is logged and tried again on the
    /// next pass; it never stops the exchange.
    func writeAppCatalogIfChanged(_ found: SyncGroup) async {
        let sequence = ownLast.sequence
        guard catalogCheckedAt != sequence else { return }
        do {
            let entries = try await storage.syncAppCatalogEntries()
            guard !entries.isEmpty, entries != writtenCatalog else {
                catalogCheckedAt = sequence
                return
            }
            let catalog = SyncAppCatalog(
                deviceID: identity.deviceID, epoch: found.epoch, entries: entries,
                signerKeyID: identity.keys.publicKeys.keyID
            )
            let url = layout.appCatalog(identity.deviceID)
            try folderProbe.willWrite(url)
            try folderProbe.writeData(catalog.sealed(syncKey: found.key, signedBy: identity.keys), url)
            writtenCatalog = entries
            catalogCheckedAt = sequence
        } catch {
            logger.error("The app catalog was not written: \(String(describing: error), privacy: .public)")
        }
    }

    /// Reads the other devices' app catalogs. A missing, damaged or refused one is skipped.
    func readAppCatalogs(of devices: [String], _ found: SyncGroup) {
        guard let onAppCatalog else { return }
        var entries: [SyncAppCatalog.Entry] = []
        for device in devices {
            let url = layout.appCatalog(device)
            guard let changed = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  readCatalogDates[device] != changed else { continue }
            guard let data = SyncSmallFile.read(url),
                  let catalog = try? SyncAppCatalog.open(
                      data, syncKey: found.key, trust: found.trust, deviceID: device, epoch: found.epoch
                  ) else { continue }
            readCatalogDates[device] = changed
            entries += catalog.entries
        }
        if !entries.isEmpty { onAppCatalog(SyncAppCatalog.bounded(entries)) }
    }
}

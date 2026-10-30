// SPDX-License-Identifier: MIT
import Foundation

enum SyncGroupSurvey {
    /// How many clips the other Macs' logs hold right now: each distinct text once, less what a later deletion took.
    /// It reads every segment once, so it is for the one question a joining Mac asks ("the group has N clips").
    static func clipCount(layout: SyncFolderLayout, group: SyncGroup, excluding device: String) -> Int {
        var added: [String: SyncStamp] = [:]
        var removed: [String: SyncStamp] = [:]
        for id in layout.deviceIDs() where id != device {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: layout.log(id).path)) ?? [])
                .filter { $0.hasSuffix(".pestolog") }.sorted()
            for name in names {
                guard let data = try? Data(contentsOf: layout.log(id).appendingPathComponent(name)),
                      let segment = try? SyncSegmentReader.verify(
                          data, syncKey: group.key, trust: group.trust, vaultID: group.vault.vaultID, epoch: group.epoch
                      ),
                      let records = try? segment.records() else { continue }
                for record in records {
                    switch record.kind {
                    case .item:
                        if let hash = (try? record.decodeMetadata(SyncItemRecord.self))?.plainHash {
                            added[hash] = max(added[hash] ?? .origin, record.stamp)
                        }
                    case .tombstone:
                        if let meta = try? record.decodeMetadata(SyncTombstoneRecord.self), meta.kind == .item,
                           let hash = meta.plainHash
                        {
                            removed[hash] = max(removed[hash] ?? .origin, record.stamp)
                        }
                    default: break
                    }
                }
            }
        }
        return added.count(where: { hash, stamp in (removed[hash] ?? .origin) < stamp })
    }
}

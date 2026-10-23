// SPDX-License-Identifier: MIT
import Foundation

public enum RestoreWarning: Equatable, Sendable {
    case olderThanThisMac

    /// A restore is flagged when the backup came from this Mac and is older than the last backup this Mac made, so
    /// the person is told before older clips and settings of theirs are mixed back in.
    public static func evaluate(manifest: BackupManifest, lastLocalSequence: UInt64, localDeviceID: String) -> Self? {
        guard manifest.deviceID == localDeviceID, manifest.sequence < lastLocalSequence else { return nil }
        return .olderThanThisMac
    }
}

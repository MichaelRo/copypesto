// SPDX-License-Identifier: MIT
import PestoCore

extension CardFootLine {
    static func origin(of item: ClipboardItem, peerDeviceNames: [String: String] = [:]) -> Origin {
        Origin(
            isRemote: item.isRemote,
            appName: item.knownSourceAppName,
            arrivedBySync: item.syncOrigin != nil,
            deviceName: item.syncOrigin.flatMap { peerDeviceNames[$0] },
            captureMethod: item.captureMethod
        )
    }
}

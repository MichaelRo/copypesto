// SPDX-License-Identifier: MIT
import PestoCore

extension CardFootLine {
    static func origin(of item: ClipboardItem) -> Origin {
        Origin(
            isRemote: item.isRemote, appName: item.knownSourceAppName, arrivedBySync: item.syncOrigin != nil,
            captureMethod: item.captureMethod
        )
    }
}

// SPDX-License-Identifier: MIT
import Foundation

/// What kind of device is speaking, so a sync sentence says "this iPhone" on an iPhone. A Mac's sentences are the ones
/// it always had; on an iPhone or iPad the others are "your other devices", because a Mac is not the only kind there.
public enum SyncDeviceKind: String, Sendable, CaseIterable {
    case mac
    case iPhone
    case iPad

    public var name: String {
        switch self {
        case .mac: "Mac"
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        }
    }

    public var thisDevice: String {
        "this \(name)"
    }
}

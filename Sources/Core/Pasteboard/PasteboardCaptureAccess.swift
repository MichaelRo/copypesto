// SPDX-License-Identifier: MIT
import AppKit

public protocol PasteboardAccessProviding: Sendable {
    var behaviorRawValue: Int { get }
}

public struct SystemPasteboardAccess: PasteboardAccessProviding {
    public init() {}

    public var behaviorRawValue: Int {
        if #available(macOS 15.4, *) {
            return AppPasteboard.reader.accessBehavior.rawValue
        }
        return PasteboardCaptureAccess.alwaysAllowRawValue
    }
}

/// macOS 15.4+ lets the user make an app's programmatic pasteboard access ask every time or be denied,
/// which silently stops a clipboard manager from capturing.
public enum PasteboardCaptureAccess: Equatable, Sendable {
    case allowed
    case notDecided
    case prompting
    case blocked

    static let alwaysAllowRawValue = 2

    public init(behaviorRawValue: Int) {
        switch behaviorRawValue {
        case 0: self = .notDecided
        case 1: self = .prompting
        case 3: self = .blocked
        default: self = .allowed
        }
    }

    public static func current(from provider: any PasteboardAccessProviding = SystemPasteboardAccess()) -> Self {
        Self(behaviorRawValue: provider.behaviorRawValue)
    }

    /// macOS has not been told to allow this yet, so the first read of the board can raise its own alert.
    public var asksOrWillAsk: Bool {
        self == .notDecided || self == .prompting
    }

    public var needsAttention: Bool {
        self == .prompting || self == .blocked
    }
}

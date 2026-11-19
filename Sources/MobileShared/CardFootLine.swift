// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

struct CardFootLine: Equatable {
    struct Device: Equatable {
        let name: String
        let symbol: String
    }

    let symbol: String?
    let texts: [String]

    struct Origin: Equatable {
        var isRemote = false
        var appName: String?
        var arrivedBySync = false
        var captureMethod: CaptureMethod?
    }

    static func make(
        _ origin: Origin, title: String?, age: String, device: Device, showsTitleOnFace: Bool = false
    )
    -> CardFootLine {
        let source = source(origin, device: device)
        let symbol = source.isThisDevice ? device.symbol : nil
        let cleanTitle = title.flatMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let texts = CardMetaLine.candidates(
            .init(title: cleanTitle, source: source.name, age: age, showsTitleOnFace: showsTitleOnFace)
        )
        return CardFootLine(symbol: (cleanTitle == nil || showsTitleOnFace) ? symbol : nil, texts: texts)
    }

    /// Where the clip came from, as the foot line and the widget name it: the app, another device, nothing for a synced
    /// clip without a name, or for one made here how it came in (or the device).
    static func source(_ origin: Origin, device: Device) -> (name: String?, isThisDevice: Bool) {
        if origin.isRemote { return (PasteboardCapture.remoteSourceName, false) }
        if let appName = origin.appName { return (appName, false) }
        if origin.arrivedBySync { return (nil, false) }
        return (origin.captureMethod.map(label) ?? device.name, true)
    }

    /// How a clip made on this device came in, in place of the device's name (ADR 0049).
    static func label(_ method: CaptureMethod) -> String {
        switch method {
        case .paste: String(localized: "Pasted")
        case .note: String(localized: "Note")
        case .share: String(localized: "Shared")
        case .drop: String(localized: "Dropped")
        case .shortcut: String(localized: "Shortcut")
        }
    }
}

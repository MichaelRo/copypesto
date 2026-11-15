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

    static func make(_ origin: Origin, title: String?, age: String, device: Device) -> CardFootLine {
        let source: String?
        var symbol: String?
        if origin.isRemote {
            source = PasteboardCapture.remoteSourceName
        } else if let appName = origin.appName {
            source = appName
        } else if origin.arrivedBySync {
            source = nil
        } else {
            source = origin.captureMethod.map(label) ?? device.name
            symbol = device.symbol
        }
        let cleanTitle = title.flatMap { $0.isEmpty ? nil : $0 }
        let texts = CardMetaLine.candidates(.init(title: cleanTitle, source: source, age: age))
        return CardFootLine(symbol: cleanTitle == nil ? symbol : nil, texts: texts)
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

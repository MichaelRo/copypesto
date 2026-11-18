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
            source = device.name
            symbol = device.symbol
        }
        let cleanTitle = title.flatMap { $0.isEmpty ? nil : $0 }
        let texts = CardMetaLine.candidates(.init(title: cleanTitle, source: source, age: age))
        return CardFootLine(symbol: cleanTitle == nil ? symbol : nil, texts: texts)
    }
}

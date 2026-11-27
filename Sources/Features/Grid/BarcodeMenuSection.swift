// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct BarcodeMenuSection: View {
    let item: ClipboardItem
    let loadImageData: () -> Data?
    let openURL: ((URL) -> Void)?
    let copyText: (ClipboardItem, String) -> Void
    var copySecretText: ((ClipboardItem, String) -> Void)?

    var body: some View {
        let payloads = BarcodeDetector.cachedOrDetect(
            id: item.id,
            contentHash: item.contentHash,
            imageData: loadImageData
        )
        if !payloads.isEmpty {
            Section(payloads.first?.kind.label ?? String(localized: "QR Code")) {
                ForEach(payloads.prefix(3), id: \.self) { payload in
                    if let url = payload.urlToOpen, let openURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open Link from \(payload.kind.label)", systemImage: "safari")
                        }
                    }
                    Button {
                        if payload.copiesAsSecret, let copySecretText {
                            copySecretText(item, payload.copyableValue)
                        } else {
                            copyText(item, payload.copyableValue)
                        }
                    } label: {
                        Label(payload.copyActionTitle, systemImage: payload.kind.symbolName)
                    }
                    if let secondaryTitle = payload.secondaryCopyTitle,
                       let secondaryValue = payload.secondaryCopyValue
                    {
                        Button {
                            copyText(item, secondaryValue)
                        } label: {
                            Label(secondaryTitle, systemImage: "wifi")
                        }
                    }
                }
            }
        }
    }
}

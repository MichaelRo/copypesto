// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// On-demand QR and barcode actions for an unlocked, non-concealed image clip on iOS.
struct BarcodeActionsMenu: View {
    let item: ClipboardItem
    let isConcealed: Bool

    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @State private var payloads: [BarcodePayload] = []

    private var isEligible: Bool {
        item.type == .image
            && !isConcealed
            && item.sensitivityRaw == nil
            && !item.analysisPending
            && !appState.isHistoryLockedNow()
    }

    var body: some View {
        Group {
            if isEligible {
                ForEach(payloads, id: \.self) { payload in
                    if let url = payload.urlToOpen {
                        Button("Open Link from \(payload.kind.label)", systemImage: "safari") {
                            appState.openExternally(url)
                        }
                    }
                    Button(payload.copyActionTitle, systemImage: payload.kind.symbolName) {
                        if copyValue(payload.copyableValue, isSecret: payload.copiesAsSecret) {
                            library.didCopy(item.id)
                        }
                    }
                    if let secondaryTitle = payload.secondaryCopyTitle,
                       let secondaryValue = payload.secondaryCopyValue
                    {
                        Button(secondaryTitle, systemImage: "wifi") {
                            if copyValue(secondaryValue, isSecret: false) {
                                library.didCopy(item.id)
                            }
                        }
                    }
                }
            }
        }
        .task(id: item.id) {
            guard isEligible else {
                payloads = []
                return
            }
            let imageData: Data? = if let container = appState.historyContainer {
                await ClipContent.payload(itemID: item.id, container: container)
            } else {
                item.blob?.decryptedData()
            }
            guard let imageData, isEligible else {
                payloads = []
                return
            }
            payloads = await BarcodeDetector.detect(in: imageData)
        }
    }

    private func copyValue(_ text: String, isSecret: Bool) -> Bool {
        let protected = isSecret || item.sensitivityRaw != nil
        MobileClipboard.write(.text(text), protected: protected)
        appState.tell(String(localized: "Copied"))
        return true
    }
}

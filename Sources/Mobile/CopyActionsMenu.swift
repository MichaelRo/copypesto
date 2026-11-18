// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Copy As, Copy Recognized Text and Save to Photos, in a card's menu and the detail's More menu, for the clips that
/// offer them (`CardCopyActions`). The transforms are the Mac's, grouped as its menu groups them.
struct CopyActionsMenu: View {
    let item: ClipboardItem
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library

    var body: some View {
        let offer = appState.copyOffer(for: item)
        if offer.offersDecodeJWT {
            Button("Decode JWT", systemImage: "curlybraces") { Task { await appState.decodeJWT(item) } }
        }
        if !offer.structured.isEmpty || !offer.transforms.isEmpty {
            Menu("Copy As", systemImage: "doc.on.doc.badge.gearshape") {
                if !offer.structured.isEmpty {
                    rows(offer.structured)
                    Divider()
                }
                transformRows(offer.transforms)
            }
        }
        if !offer.colorFormats.isEmpty {
            Menu("Copy As", systemImage: "eyedropper") {
                ForEach(offer.colorFormats, id: \.self) { format in
                    Button(format.title) { didCopy(appState.copyColor(item, as: format)) }
                }
            }
        }
        if offer.offersRecognizedText {
            Button("Copy Recognized Text", systemImage: "text.viewfinder") {
                Task { await didCopy(appState.copyRecognizedText(of: item), flashes: false) }
            }
        }
        if offer.offersSaveToPhotos {
            Button("Save to Photos", systemImage: "square.and.arrow.down") {
                Task { await appState.saveToPhotos(item) }
            }
        }
    }

    @ViewBuilder
    private func transformRows(_ transforms: [TextTransform]) -> some View {
        let sections = TextTransform.grouped(transforms)
        ForEach(sections.filter { !$0.group.isSubmenu }, id: \.group) { section in
            rows(section.transforms)
        }
        ForEach(sections.filter(\.group.isSubmenu), id: \.group) { section in
            Menu(section.group.title) { rows(section.transforms) }
        }
    }

    private func rows(_ transforms: [TextTransform]) -> some View {
        ForEach(transforms, id: \.self) { transform in
            Button(transform.rawValue, systemImage: transform.symbolName) {
                didCopy(appState.copyTransformed(item, by: transform))
            }
        }
    }

    private func didCopy(_ copied: Bool, flashes: Bool = true) {
        if copied, flashes { library.didCopy(item.id) }
    }
}

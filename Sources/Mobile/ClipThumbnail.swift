// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import UIKit

/// A picture clip's picture, made off the main thread by the store's one `ThumbnailService` and kept in
/// `ThumbnailCache` at row size, so scrolling back to a row does not open the picture again.
struct ClipThumbnail: View {
    /// The size a row asks for; the detail view's larger picture is not kept in the shared cache.
    static let rowPixel = 240

    let itemID: UUID
    let byteSize: Int
    let maxPixel: Int
    @Environment(MobileAppState.self) private var appState
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.12)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .accessibilityHidden(true)
        .task(id: itemID) { await load() }
    }

    private func load() async {
        let caches = maxPixel <= Self.rowPixel
        if caches, let cached = ThumbnailCache.shared.entry(for: itemID, byteSize: byteSize) {
            image = cached.image
            return
        }
        guard let container = appState.historyContainer else { return }
        let service = await ThumbnailServices.shared.service(for: container)
        guard let thumbnail = await service.thumbnail(for: itemID, maxPixel: maxPixel),
              let made = UIImage(data: thumbnail.data) else { return }
        if caches {
            ThumbnailCache.shared.store(
                .init(image: made, isAnimated: thumbnail.isAnimated, byteSize: byteSize), for: itemID
            )
        }
        image = made
    }
}

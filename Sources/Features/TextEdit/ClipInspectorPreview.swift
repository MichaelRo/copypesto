// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import QuickLookThumbnailing
import SwiftData
import SwiftUI

/// The Clip window's content for a clip it does not edit (ADR 0071): a picture as large as the pane allows, a file
/// as its Quick Look preview (several as a list), and anything else as its hover card. The caller decides whether
/// the clip may be shown at all (`CardConcealment`).
struct ClipInspectorPreview: View {
    let item: ClipboardItem
    @State private var picture: NSImage?
    @State private var pictureIsAnimated = false
    @State private var fileThumbnail: NSImage?
    @State private var missing: [URL] = []
    @Environment(\.modelContext) private var modelContext

    /// Twice the pane's width on a Retina display; the full-resolution bitmap is never decoded.
    static let pictureMaxPixel = 1024
    private static let fileThumbnailSide: CGFloat = 320

    init(item: ClipboardItem, picture: NSImage? = nil, pictureIsAnimated: Bool = false, fileThumbnail: NSImage? = nil) {
        self.item = item
        let cached = ThumbnailCache.shared.entry(for: item.id, byteSize: item.byteSize)
        _picture = State(initialValue: picture ?? cached?.image)
        _pictureIsAnimated = State(initialValue: picture == nil ? cached?.isAnimated ?? false : pictureIsAnimated)
        _fileThumbnail = State(initialValue: fileThumbnail)
    }

    var body: some View {
        switch item.type {
        case .image:
            pictureBody
                .task(id: item.id) { await loadPicture() }
        case .file:
            fileBody
                .task(id: item.id) { await loadFiles() }
        default:
            ScrollView {
                CardDetailPopover(item: item).frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var pictureBody: some View {
        Group {
            if let picture {
                if pictureIsAnimated {
                    AnimatedImageView(
                        image: picture, animates: !Motion.reduceMotion,
                        contentMode: .scaleProportionallyUpOrDown, aspectFit: true
                    )
                } else {
                    Image(nsImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Picture")
        .accessibilityIdentifier(AccessibilityID.clipInspectorPreview)
    }

    private var fileURLs: [URL] {
        FileClip.urls(from: ClipText.full(of: item))
    }

    @ViewBuilder
    private var fileBody: some View {
        let urls = fileURLs
        VStack(spacing: 12) {
            if urls.count == 1, let url = urls.first {
                Image(nsImage: fileThumbnail ?? Self.icon(for: url, exists: !missing.contains(url)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: Self.fileThumbnailSide, maxHeight: Self.fileThumbnailSide)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
                fileRow(url)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(urls, id: \.self) { fileRow($0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.clipInspectorPreview)
    }

    private func fileRow(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: Self.icon(for: url, exists: !missing.contains(url)))
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(verbatim: url.deletingLastPathComponent().path)
                    .pestoCaption()
                    .lineLimit(1)
                    .truncationMode(.head)
                if missing.contains(url) {
                    Text("Moved or deleted").pestoCaption()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private static func icon(for url: URL, exists: Bool) -> NSImage {
        if exists { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .init(filenameExtension: url.pathExtension) ?? .data)
    }

    private func loadPicture() async {
        let id = item.id
        let service = await ThumbnailServices.shared.service(for: modelContext.container)
        guard !Task.isCancelled,
              let result = await service.thumbnail(for: id, maxPixel: Self.pictureMaxPixel),
              let image = await PreparedImage.image(from: result.data, animated: result.isAnimated),
              !Task.isCancelled else { return }
        picture = image
        pictureIsAnimated = result.isAnimated
    }

    /// Read off the main thread: a file on a stalled volume must not freeze the window.
    private func loadFiles() async {
        let text = ClipText.full(of: item)
        missing = await FileClip.missing(inText: text)
        let urls = FileClip.urls(from: text)
        guard urls.count == 1, let url = urls.first, missing.isEmpty else { return }
        guard await !Task.detached(priority: .utility, operation: { FileClip.isFolder(url) }).value else { return }
        let side = Self.fileThumbnailSide
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
              !Task.isCancelled else { return }
        fileThumbnail = NSImage(cgImage: representation.cgImage, size: representation.contentRect.size)
    }
}

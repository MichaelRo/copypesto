// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import QuickLookThumbnailing
import SwiftUI

/// What a file clip shows on its card: the file's icon or a preview of it, its name, and where it lives. Pesto keeps
/// only the path, so a file that has moved or been deleted says so.
struct FileCardBody: View {
    let text: String
    /// Whether an animated picture plays (the card is in focus or under the pointer, or auto-play is allowed).
    var animates = false
    /// A GIF file is read at most this big to be played on the card; a larger one keeps its still icon.
    private nonisolated static let maxAnimatedBytes = 10 * 1024 * 1024
    @State private var animatedPicture: NSImage?
    @State private var thumbnail: NSImage?
    /// Which files are gone and the icon of a single file: both are read off the main thread by `.task`, never while
    /// the
    /// card draws, because a file on a stalled network volume would freeze the shelf.
    @State private var missing: [URL] = []
    @State private var fileIcon: NSImage?

    private var urls: [URL] {
        FileClip.urls(from: text)
    }

    private var summary: FileClip.Summary {
        FileClip.summary(of: text)
    }

    var body: some View {
        Group {
            if let animatedPicture {
                animatedBody(animatedPicture)
            } else {
                plainBody
            }
        }
        // On the wrapper, not on a branch: a task on the branch restarts whenever the branch swaps in, which reset
        // the picture it had just loaded.
        .task(id: text) { await loadThumbnail() }
    }

    private func animatedBody(_ picture: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AnimatedImageView(image: picture, animates: animates)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(summary.title)
                .scaledFont(size: 11, weight: .medium, maxScale: 1.3)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var plainBody: some View {
        HStack(alignment: .center, spacing: 9) {
            iconView
                .frame(width: 44, height: 44)
                .opacity(missing.isEmpty ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    // Text size capped: fills a fixed-size card.
                        .scaledFont(size: 12, weight: .semibold, maxScale: 1.3)
                        .lineLimit(2)
                        .truncationMode(.middle)
                Text(summary.subtitle)
                    .font(.caption2)
                    .pestoQuiet()
                    .lineLimit(2)
                if !missing.isEmpty {
                    Label(missingLabel, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(Color.statusWarning)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var missingLabel: String {
        guard urls.count > 1 else { return String(localized: "Moved or deleted") }
        return String(localized: "\(missing.count) moved or deleted")
    }

    @ViewBuilder
    private var iconView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
        } else if urls.count > 1 {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 26))
                .pestoQuiet()
        } else if let fileIcon {
            Image(nsImage: fileIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "doc").font(.system(size: 26)).pestoQuiet()
        }
    }

    private static func icon(for url: URL, exists: Bool) -> NSImage {
        if exists { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .init(filenameExtension: url.pathExtension) ?? .data)
    }

    /// Read off the main thread: a file on a stalled volume must not freeze the shelf.
    private static func loadAnimated(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  size <= maxAnimatedBytes, let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        }.value
    }

    private func loadThumbnail() async {
        thumbnail = nil
        missing = await FileClip.missing(inText: text)
        animatedPicture = nil
        if missing.isEmpty, let gif = FileClip.animatedPictureURL(inText: text) {
            animatedPicture = await Self.loadAnimated(gif)
            if animatedPicture != nil { return }
        }
        if urls.count == 1, let url = urls.first {
            fileIcon = Self.icon(for: url, exists: missing.isEmpty)
        }
        guard urls.count == 1, let url = urls.first, missing.isEmpty else { return }
        guard await !Task.detached(priority: .utility, operation: { FileClip.isFolder(url) }).value else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 44, height: 44), scale: 2, representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnail = NSImage(cgImage: representation.cgImage, size: CGSize(width: 44, height: 44))
        }
    }
}

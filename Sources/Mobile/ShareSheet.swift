// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ClipShare: Identifiable {
    let id = UUID()
    let items: [Any]

    /// The files made for this share, removed when the share sheet is done.
    var files: [URL] {
        items.compactMap { $0 as? URL }.filter { ShareFile.owns($0) }
    }

    init(_ content: ClipContent) {
        items = switch content {
        case let .text(text): [text]
        case let .link(url, _): [url]
        case let .picture(data, type): Self.pictureItems(data, typeIdentifier: type)
        }
    }

    /// A GIF goes out as a file of its own, because a `UIImage` made from it is its first frame; any other picture
    /// goes as the image.
    static func pictureItems(_ data: Data, typeIdentifier: String) -> [Any] {
        if typeIdentifier == UTType.gif.identifier || data.isGIF,
           let file = try? ShareFile.write(data, fileExtension: "gif")
        {
            return [file]
        }
        return [UIImage(data: data) ?? data]
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var files: [URL] = []

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in files.forEach(ShareFile.remove) }
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

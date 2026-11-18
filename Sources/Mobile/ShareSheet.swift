// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

struct ClipShare: Identifiable {
    let id = UUID()
    let items: [Any]

    init(_ content: ClipContent) {
        items = switch content {
        case let .text(text): [text]
        case let .link(url, _): [url]
        case let .picture(data, _): [UIImage(data: data) ?? data]
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

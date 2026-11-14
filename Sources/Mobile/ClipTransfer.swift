// SPDX-License-Identifier: MIT
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A clip handed to Share or dragged out of Pesto on iPad: text as text, a link as a URL and its text, a picture as
/// its own bytes.
struct ClipTransfer: Transferable {
    let content: ClipContent

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { transfer in
            transfer.pictureData ?? Data()
        }
        .exportingCondition { $0.pictureType == UTType.png.identifier }
        DataRepresentation(exportedContentType: .jpeg) { transfer in
            transfer.pictureData ?? Data()
        }
        .exportingCondition { $0.pictureType == UTType.jpeg.identifier }
        DataRepresentation(exportedContentType: .image) { transfer in
            transfer.pictureData ?? Data()
        }
        .exportingCondition { $0.pictureData != nil }
        ProxyRepresentation { transfer in
            transfer.url ?? URL(fileURLWithPath: "/")
        }
        .exportingCondition { $0.url != nil }
        ProxyRepresentation { transfer in
            transfer.content.plainText ?? ""
        }
        .exportingCondition { $0.content.plainText != nil }
    }

    private var pictureData: Data? {
        if case let .picture(data, _) = content { data } else { nil }
    }

    private var pictureType: String? {
        if case let .picture(_, type) = content { type } else { nil }
    }

    private var url: URL? {
        if case let .link(url, _) = content { url } else { nil }
    }
}

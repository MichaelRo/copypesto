// SPDX-License-Identifier: MIT
import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// A picture clip handed to Share from the detail: the original is opened only when a share is chosen, because the
/// detail itself shows the thumbnail's copy.
struct DeferredPictureTransfer: Transferable {
    struct Missing: Error {}

    let itemID: UUID
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .image) { transfer in
            guard case let .picture(data, _)? = await ClipContent.load(
                itemID: transfer.itemID, container: transfer.container
            ) else { throw Missing() }
            return data
        }
    }
}

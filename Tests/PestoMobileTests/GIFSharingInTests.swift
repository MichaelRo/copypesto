// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PestoCore
@testable import PestoMobile

@Suite("Handing Pesto an animated GIF")
@MainActor
struct GIFSharingInTests {
    @Test("a GIF offered beside a still copy of its first frame is captured whole")
    func whenAGIFComesWithAStill_thenTheGIFIsKept() async throws {
        let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3B])
        let still = try #require(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { _ in })
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) {
            $0(still, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.gif.identifier, visibility: .all) {
            $0(gif, nil)
            return nil
        }

        let capture = try await ItemProviderCapture.capture(from: [provider])

        #expect(capture?.typeIdentifier == UTType.gif.identifier)
        #expect(capture?.payload == gif)
    }
}

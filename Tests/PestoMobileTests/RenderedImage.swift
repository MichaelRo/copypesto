// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit

/// A rendered view for a test: its pixels to compare, and a PNG beside the repository for a person to look at. A CI
/// simulator sometimes fails to encode a PNG ("zlib error, No IDATs written"), so the picture is best effort and never
/// what a test checks.
enum RenderedImage {
    static func pixels(_ image: UIImage) throws -> Data {
        let cgImage = try #require(image.cgImage, "the renderer drew no bitmap")
        let data = try #require(cgImage.dataProvider?.data as Data?, "the bitmap has no pixels")
        #expect(!data.isEmpty)
        return data
    }

    static func saveForReview(_ image: UIImage, to url: URL) {
        guard let png = image.pngData() else { return }
        try? png.write(to: url)
    }
}

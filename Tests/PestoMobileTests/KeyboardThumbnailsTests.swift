// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit

/// A picture card is drawn again each time the row scrolls back to it, so its picture and the blurred ground behind a
/// picture that does not fill are made once, ready to draw.
@Suite("Keyboard thumbnails are decoded once")
@MainActor
struct KeyboardThumbnailsTests {
    private static func jpeg(width: Int, height: Int) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }

    @Test("the same entry's picture is the same object the second time")
    func whenAskedTwice_thenCached() throws {
        let thumbnails = KeyboardThumbnails()
        let id = UUID()
        let data = try Self.jpeg(width: 240, height: 120)
        let first = try #require(thumbnails.picture(for: id, data: data))
        let second = try #require(thumbnails.picture(for: id, data: data))
        #expect(first.image === second.image)
        #expect(first.backdrop === second.backdrop)
    }

    @Test("a picture comes with a backdrop the size of the picture or smaller")
    func whenDecoded_thenBackdropIsMade() throws {
        let thumbnails = KeyboardThumbnails()
        let picture = try #require(thumbnails.picture(for: UUID(), data: Self.jpeg(width: 240, height: 120)))
        let backdrop = try #require(picture.backdrop)
        #expect(backdrop.size.width <= picture.image.size.width)
    }

    @Test("data that is not a picture gives nothing and is not kept")
    func whenNotAPicture_thenNil() {
        let thumbnails = KeyboardThumbnails()
        #expect(thumbnails.picture(for: UUID(), data: Data("not a picture".utf8)) == nil)
    }
}

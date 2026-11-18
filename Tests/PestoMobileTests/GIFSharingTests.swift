// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PestoCore
@testable import PestoMobile

@Suite("Sharing a GIF out of Pesto")
struct GIFSharingTests {
    private static let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3B])

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pesto-share-test-\(UUID().uuidString)")
    }

    @Test("a GIF is shared as a .gif file with every byte, never as an image of its first frame")
    func whenAGIFIsShared_thenTheItemIsTheFile() throws {
        let items = ClipShare.pictureItems(Self.gif, typeIdentifier: UTType.gif.identifier)
        let url = try #require(items.first as? URL)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(items.count == 1)
        #expect(url.pathExtension == "gif")
        #expect(try Data(contentsOf: url) == Self.gif)
    }

    @Test("a GIF whose stored type was not labelled is still recognized by its header")
    func whenTheTypeIsMissing_thenTheHeaderDecides() throws {
        let url = try #require(ClipShare.pictureItems(Self.gif, typeIdentifier: UTType.png.identifier).first as? URL)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(url.pathExtension == "gif")
    }

    @Test("any other picture is shared as an image")
    func whenAPNGIsShared_thenTheItemIsAnImage() throws {
        let png = try #require(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { _ in })
        let items = ClipShare.pictureItems(png, typeIdentifier: UTType.png.identifier)
        #expect(items.first is UIImage)
    }

    @Test("a share file is written in a folder of its own, and folders older than an hour are swept")
    func whenAFileIsWritten_thenOldFoldersGo() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try ShareFile.write(Self.gif, fileExtension: "gif", in: root, now: .now)
        let later = Date.now.addingTimeInterval(ShareFile.lifetime + 60)
        let fresh = try ShareFile.write(Self.gif, fileExtension: "gif", in: root, now: later)

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(fresh.lastPathComponent == "Pesto.gif")
    }
}

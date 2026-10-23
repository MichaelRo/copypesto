// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import Testing
@testable import PestoCore

@Suite("Files copied on another device")
struct RemoteFileClipTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("pesto-remote-\(UUID().uuidString)", isDirectory: true)

    private func file(_ name: String, bytes: Int = 64) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    @Test("one photo is kept as its bytes, typed by its extension, so it outlives the temporary file")
    func whenOnePhoto_thenItsBytes() throws {
        let jpeg = try file("IMG_1.jpeg", bytes: 200)
        let picture = try #require(RemoteFileClip.picture(from: [jpeg]))
        #expect(picture.type.rawValue == "public.jpeg")
        #expect(picture.data.count == 200)
        let heic = try file("IMG_2.heic")
        #expect(RemoteFileClip.picture(from: [heic])?.type.rawValue == "public.heic")
        let png = try file("shot.png")
        #expect(RemoteFileClip.picture(from: [png])?.type == .png)
    }

    @Test("anything that is not one supported picture is not kept: a PDF, text, two photos, an unsupported image")
    func whenNotOnePicture_thenNotKept() throws {
        #expect(try RemoteFileClip.picture(from: [file("flight.pdf")]) == nil)
        #expect(try RemoteFileClip.picture(from: [file("notes.txt")]) == nil)
        #expect(try RemoteFileClip.picture(from: [file("a.jpeg"), file("b.jpeg")]) == nil)
        #expect(try RemoteFileClip.picture(from: [file("old.bmp")]) == nil)
        #expect(RemoteFileClip.picture(from: []) == nil)
        #expect(RemoteFileClip.picture(from: [folder.appendingPathComponent("gone.jpeg")]) == nil)
    }

    @Test("a photo over the size limit is refused before it is read")
    func whenTooLarge_thenNotReadAtAll() throws {
        let jpeg = try file("big.jpeg")
        var reads = 0
        let picture = RemoteFileClip.picture(
            from: [jpeg],
            byteCount: { _ in ClipSizePolicy.maxOtherBytes + 1 },
            read: { _ in
                reads += 1
                return Data([1])
            }
        )
        #expect(picture == nil)
        #expect(reads == 0)
    }
}

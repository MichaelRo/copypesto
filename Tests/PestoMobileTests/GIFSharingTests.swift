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

    @Test(
        "a share file is sealed by the device's file protection, owned by the share folder, and removed with its folder"
    )
    func whenAFileIsWritten_thenItIsProtectedAndRemovable() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try ShareFile.write(Self.gif, fileExtension: "gif", in: root)
        let protection = try FileManager.default
            .attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType
        #expect(protection == .complete || protection == nil, "the simulator may not report one")
        #expect(ShareFile.owns(file, in: root))
        #expect(!ShareFile.owns(URL(fileURLWithPath: "/tmp/other.gif"), in: root))
        ShareFile.remove(file)
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
    }

    @Test("a share's files are the ones in the share folder, and only those")
    func whenItemsAreShared_thenOnlyOurFilesAreListed() {
        let share = ClipShare(.picture(Self.gif, typeIdentifier: UTType.gif.identifier))
        defer { ShareFile.removeAll() }
        #expect(share.files.count == 1)
        #expect(ClipShare(.text("words")).files.isEmpty)
    }

    @Test("locking the history and Clear History take every share file away")
    @MainActor
    func whenTheHistoryLocksOrClears_thenTheShareFolderIsEmpty() async throws {
        let lock = MobileHistoryLock(
            authenticator: StubUserAuthenticator(available: true, grants: true), grace: AuthenticationGrace(),
            isEnabled: { true }
        )
        let library = try await MobileTestLibrary(lock: lock)
        _ = try ShareFile.write(Self.gif, fileExtension: "gif")
        library.state.lockHistory()
        #expect(!FileManager.default.fileExists(atPath: ShareFile.directory.path))

        _ = try ShareFile.write(Self.gif, fileExtension: "gif")
        await library.state.clearHistory()
        #expect(!FileManager.default.fileExists(atPath: ShareFile.directory.path))

        _ = try ShareFile.write(Self.gif, fileExtension: "gif")
        library.state.didLeaveForeground()
        #expect(!FileManager.default.fileExists(atPath: ShareFile.directory.path))
    }
}

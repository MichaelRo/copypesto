// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

@Suite("The sealed inbox the share extension writes")
struct SharedInboxTests {
    private func temporaryInbox() throws -> SharedInbox {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-inbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return SharedInbox(root: root)
    }

    private func published(_ inbox: SharedInbox) throws -> Curve25519.KeyAgreement.PrivateKey {
        let key = try InboxKeyStore(secrets: MemorySecrets()).loadOrCreate()
        try inbox.publish(InboxPublicKey(key.publicKey))
        return key
    }

    private let date = Date(timeIntervalSince1970: 1_800_000_000.123)

    @Test("text, a link and a picture's bytes open with the private key exactly as they were sealed")
    func whenSealedToThePublicKey_thenTheyOpen() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let picture = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let menu = try #require(URL(string: "https://example.com/menu?day=1"))
        let items = try [
            #require(InboxItem.text("lunch at noon? \u{1F96A}", at: date)),
            #require(InboxItem.link(menu, at: date)),
            InboxItem(typeIdentifier: "public.png", payload: picture, createdAt: date)
        ]

        for item in items {
            let sealed = try InboxEnvelope.seal(item, to: InboxPublicKey(key.publicKey))
            let opened = try InboxEnvelope.open(sealed, with: key)
            #expect(opened.typeIdentifier == item.typeIdentifier)
            #expect(opened.payload == item.payload)
            #expect(opened.sourceImageURL == nil)
            #expect(abs(opened.createdAt.timeIntervalSince(item.createdAt)) < 0.002)
            #expect(sealed.range(of: item.payload) == nil, "the payload is in the file in the clear")
        }
    }

    @Test("a picture with a sourceImageURL round-trips through the envelope, and version 1 payloads still parse")
    func whenSourceImageURLOrVersion1_thenBothOpen() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let picture = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let gifURL = try #require(URL(string: "https://media.giphy.com/media/abc/giphy.gif"))
        let item = InboxItem(
            typeIdentifier: "public.png", payload: picture, createdAt: date, sourceImageURL: gifURL
        )

        let sealed = try InboxEnvelope.seal(item, to: InboxPublicKey(key.publicKey))
        let opened = try InboxEnvelope.open(sealed, with: key)
        #expect(opened.typeIdentifier == "public.png")
        #expect(opened.payload == picture)
        #expect(opened.sourceImageURL == gifURL)
        #expect(abs(opened.createdAt.timeIntervalSince(date)) < 0.002)

        // An explicit version 1 plaintext (version, 8-byte millis, 2-byte type length, type, payload).
        let type = Data("public.png".utf8)
        let millis = UInt64(bitPattern: Int64((date.timeIntervalSince1970 * 1000).rounded()))
        var v1 = Data([1])
        v1.append(contentsOf: (0..<8).reversed().map { UInt8(truncatingIfNeeded: millis >> (8 * $0)) })
        v1.append(contentsOf: [UInt8(type.count >> 8), UInt8(truncatingIfNeeded: type.count)])
        v1.append(type)
        v1.append(picture)
        let parsedV1 = try InboxItem.parse(plaintext: v1)
        #expect(parsedV1.typeIdentifier == "public.png")
        #expect(parsedV1.payload == picture)
        #expect(parsedV1.sourceImageURL == nil)
        #expect(abs(parsedV1.createdAt.timeIntervalSince(date)) < 0.002)
    }

    @Test("a file sealed to another key, or with any byte changed, does not open")
    func whenSealedToAnotherKeyOrChanged_thenItDoesNotOpen() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let other = Curve25519.KeyAgreement.PrivateKey()
        let item = try #require(InboxItem.text("for someone else"))
        let sealed = try InboxEnvelope.seal(item, to: InboxPublicKey(other.publicKey))

        #expect(throws: InboxError.wrongKey) { try InboxEnvelope.open(sealed, with: key) }
        let mine = try InboxEnvelope.seal(item, to: InboxPublicKey(key.publicKey))
        for index in [0, 9, 30, 60, mine.count - 1] {
            var changed = mine
            changed[index] ^= 0x01
            #expect(throws: InboxError.self) { try InboxEnvelope.open(changed, with: key) }
        }
        #expect(throws: InboxError.damaged) { try InboxEnvelope.open(mine.prefix(40), with: key) }
    }

    @Test("an item of an unknown kind or over its limit is refused before anything is sealed")
    func whenUnknownOrOverTheLimit_thenRefused() throws {
        let key = InboxPublicKey(Curve25519.KeyAgreement.PrivateKey().publicKey)
        let pdf = InboxItem(typeIdentifier: "com.adobe.pdf", payload: Data([1, 2, 3]), createdAt: date)
        let huge = InboxItem(
            typeIdentifier: "public.jpeg", payload: Data(count: InboxPolicy.maxPictureBytes + 1), createdAt: date
        )

        #expect(throws: InboxError.unsupported) { try InboxEnvelope.seal(pdf, to: key) }
        #expect(throws: InboxError.tooLarge) { try InboxEnvelope.seal(huge, to: key) }
        #expect(InboxItem.text("  \n ") == nil)
        #expect(try InboxItem.link(#require(URL(string: "file:///etc/hosts"))) == nil)
    }

    @Test("the extension saves nothing when Pesto has not published its key yet")
    func whenNoPublicKey_thenTheWriterRefuses() throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.root) }

        #expect(throws: InboxError.noKey) { try inbox.deposit(#require(InboxItem.text("too early"))) }
        #expect(inbox.pendingFiles().isEmpty)
    }

    @Test("the extension refuses once the inbox holds as many files as it may")
    func whenTheInboxIsFull_thenTheWriterRefuses() throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.root) }
        _ = try published(inbox)

        for index in 0..<InboxPolicy.maxPendingFiles {
            try inbox.deposit(#require(InboxItem.text("note \(index)")))
        }

        #expect(throws: InboxError.full) { try inbox.deposit(#require(InboxItem.text("one more"))) }
        #expect(inbox.pendingFiles().count == InboxPolicy.maxPendingFiles)
    }

    @Test("a deposited file holds no plaintext and opens with the published key's private half")
    func whenDeposited_thenOnlyCiphertextIsOnDisk() throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.root) }
        let key = try published(inbox)
        let text = "reset code \(UUID().uuidString)"

        let url = try inbox.deposit(#require(InboxItem.text(text)))

        #expect(try Data(contentsOf: url).range(of: Data(text.utf8)) == nil)
        #expect(try InboxEnvelope.open(inbox.contents(of: url), with: key).text == text)
    }

    @Test("publishing the same key again leaves the file alone, and a damaged key file is replaced")
    func whenPublishedAgain_thenTheKeyIsKept() throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.root) }
        let key = try published(inbox)
        try Data("garbage".utf8).write(to: inbox.publicKeyURL)

        #expect(throws: InboxError.damaged) { try inbox.publishedKey() }
        try inbox.publish(InboxPublicKey(key.publicKey))
        #expect(try inbox.publishedKey() == InboxPublicKey(key.publicKey))
    }

    @Test("the private key is created once and read back from the store it was written to")
    func whenLoadedTwice_thenTheSameKey() throws {
        let secrets = MemorySecrets()
        let first = try InboxKeyStore(secrets: secrets).loadOrCreate()
        let second = try InboxKeyStore(secrets: secrets).loadOrCreate()

        #expect(first.rawRepresentation == second.rawRepresentation)
        #expect(try secrets.read(service: AppIdentity.keychainService, account: AppIdentity.inboxKeyAccount) != nil)
    }

    @Test("Paste, a drop and the share sheet choose a picture over a link over text")
    func choiceOrder() {
        #expect(SharedContentChoice.choose(typeIdentifiers: ["public.plain-text", "public.jpeg"]) == .picture(
            "public.jpeg"
        ))
        #expect(SharedContentChoice.choose(typeIdentifiers: ["public.plain-text", "public.url"]) == .link)
        #expect(SharedContentChoice.choose(typeIdentifiers: ["public.file-url"]) == nil)
    }

    @Test("a GIF is chosen over the still copies registered beside it, in any order")
    func whenAGIFIsOffered_thenTheWholeGIFIsChosen() {
        let gif = UTType.gif.identifier
        #expect(SharedContentChoice.choose(typeIdentifiers: ["public.png", gif]) == .picture(gif))
        #expect(SharedContentChoice
            .choose(typeIdentifiers: [gif, "public.jpeg", "public.utf8-plain-text"]) == .picture(gif))
        #expect(SharedContentChoice.choose(typeIdentifiers: ["public.png", "public.jpeg"]) == .picture("public.png"))
    }

    @Test("a picture over the limit is scaled down to a still, except a GIF, which is refused")
    func whenAPictureIsTooBig_thenOnlyAGIFIsRefused() {
        let limit = InboxPolicy.maxPictureBytes
        #expect(InboxPolicy.handling(ofStoredPictureType: UTType.gif.identifier, byteCount: limit) == .keep)
        #expect(InboxPolicy.handling(ofStoredPictureType: UTType.gif.identifier, byteCount: limit + 1) == .refuse)
        #expect(InboxPolicy.handling(ofStoredPictureType: UTType.png.identifier, byteCount: limit + 1) == .scaleDown)
        #expect(InboxPolicy.handling(ofStoredPictureType: UTType.heic.identifier, byteCount: 10) == .keep)
    }
}

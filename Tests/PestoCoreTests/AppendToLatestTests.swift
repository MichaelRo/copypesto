// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Double-copy append keeps secrets apart")
struct AppendToLatestTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
    }

    private func capture(_ text: String, concealed: Bool = false, at time: Date) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: time,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(),
            isConcealed: concealed
        )
    }

    private func items() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    @Test("an ordinary double copy is appended to the latest text clip")
    func ordinaryIsAppended() async throws {
        try await service.ingest(capture("first part", at: Date(timeIntervalSince1970: 1000)))

        try await service.appendToLatest(capture("second part", at: Date(timeIntervalSince1970: 2000)))

        let all = try items()
        #expect(all.count == 1)
        #expect(all.first?.blob?.decryptedText() == "first part\nsecond part")
    }

    @Test("a first copy that already ends with a line break gets no blank line")
    func firstCopyEndingInNewline_isJoinedWithoutBlankLine() async throws {
        try await service.ingest(capture("first line\n", at: Date(timeIntervalSince1970: 1000)))

        try await service.appendToLatest(capture("second line", at: Date(timeIntervalSince1970: 2000)))

        #expect(try items().first?.blob?.decryptedText() == "first line\nsecond line")
    }

    @Test("a first copy that ends with a blank line keeps it")
    func firstCopyEndingInBlankLine_keepsIt() async throws {
        try await service.ingest(capture("first line\n\n", at: Date(timeIntervalSince1970: 1000)))

        try await service.appendToLatest(capture("second line", at: Date(timeIntervalSince1970: 2000)))

        #expect(try items().first?.blob?.decryptedText() == "first line\n\nsecond line")
    }

    @Test("a concealed copy is never merged into a visible clip")
    func concealedIsNotAppended() async throws {
        try await service.ingest(capture("first part", at: Date(timeIntervalSince1970: 1000)))

        try await service.appendToLatest(
            capture("a password from a manager", concealed: true, at: Date(timeIntervalSince1970: 2000))
        )

        let all = try items()
        #expect(all.contains { $0.blob?.decryptedText() == "first part" }, "the visible clip must be unchanged")
        #expect(all.allSatisfy { $0.blob?.decryptedText()?.contains("first part\n") != true })
    }

    @Test("a copy is never appended to a clip that holds a secret")
    func hiddenTargetIsNotAppendedTo() async throws {
        try await service.ingest(capture("4242 4242 4242 4242", at: Date(timeIntervalSince1970: 1000)))

        try await service.appendToLatest(capture("some words", at: Date(timeIntervalSince1970: 2000)))

        let all = try items()
        #expect(all.count == 2)
        #expect(all.contains { $0.blob?.decryptedText() == "some words" })
        #expect(all.allSatisfy { $0.blob?.decryptedText()?.contains("4242 4242 4242 4242\n") != true })
    }
}

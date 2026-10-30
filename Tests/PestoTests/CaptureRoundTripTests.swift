// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import Testing
@testable import Pesto

private struct EditorFrontmost: FrontmostAppProviding {
    func frontmostBundleID() async -> String? {
        "com.example.editor"
    }

    func recentBundleIDs(within _: TimeInterval) async -> [String] {
        []
    }
}

extension HostedGlobals {
    /// The whole path a user relies on, with the real watcher, the real store and the real pasteboard write, on the
    /// harness's private pasteboard: copy in another app, capture, search, paste it back, and copy again.
    @Suite("Copy, capture, search, paste and copy again", .serialized)
    @MainActor
    struct CaptureRoundTripTests {
        private let container: ModelContainer
        private let service: StorageService
        private let state = AppState()
        private let watcher: PasteboardWatcher

        init() async throws {
            container = try ModelContainerSetup.makeInMemory()
            service = StorageService(modelContainer: container)
            watcher = PasteboardWatcher(
                pasteboard: AppPasteboard.reader, frontmostProvider: EditorFrontmost(), ownWrites: state.ownWrites
            )
            let pipeline = CapturePipeline(
                storage: service, appendMode: AppendModeCoordinator(), didStore: {}, didRefuse: { _ in }
            )
            await watcher.onCapture { await pipeline.handle($0) }
        }

        private func copyInAnotherApp(_ text: String) {
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString(text, forType: .string)
        }

        private func makeFiles(_ names: [String]) throws -> [URL] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try names.map { name in
                let url = folder.appendingPathComponent(name)
                try Data(name.utf8).write(to: url)
                return url
            }
        }

        private func items() throws -> [ClipboardItem] {
            try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
        }

        @Test(
            "a copy is captured, found by search, pasted back without a duplicate, and the next copy is not swallowed"
        )
        @MainActor
        func whenUserCopiesSearchesPastesAndCopiesAgain() async throws {
            let first = "Round trip \(UUID().uuidString) quarterly numbers"
            await watcher.tick() // sync to the board's current state

            copyInAnotherApp(first)
            await watcher.tick()

            let captured = try items()
            #expect(captured.count == 1)
            let item = try #require(captured.first)
            #expect(item.displayPreviewText == first)
            #expect(item.sourceBundleID == "com.example.editor")
            #expect(SearchMatching.matches(
                foldedText: item.searchableGridPreview,
                foldedQuery: SearchMatching.fold("QUARTERLY")
            ))
            #expect(!SearchMatching.matches(
                foldedText: item.searchableGridPreview,
                foldedQuery: SearchMatching.fold("annual")
            ))

            _ = state.writeItem(item)
            #expect(AppPasteboard.general.string(forType: .string) == first)
            await watcher.tick()
            #expect(try items().count == 1, "pasting a clip back must not capture it again")

            let second = "Second copy \(UUID().uuidString)"
            copyInAnotherApp(second)
            await watcher.tick()
            #expect(try items().count == 2, "the copy after a paste was swallowed")
            #expect(try items().last?.displayPreviewText == second)
        }

        @Test("several files copied in Finder are captured as one clip and all of them paste back")
        @MainActor
        func whenSeveralFilesCopied_thenAllPasteBack() async throws {
            let urls = try makeFiles(["basil.pdf", "pine nuts.zip", "parmesan.txt"])
            await watcher.tick()
            AppPasteboard.general.clearContents()
            AppPasteboard.general.writeObjects(urls as [NSURL])

            await watcher.tick()

            let item = try #require(try items().first)
            #expect(item.type == .file)
            #expect(FileClip.urls(from: item.displayPreviewText) == urls)

            _ = state.writeItem(item)
            let onBoard = AppPasteboard.general.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
            ) as? [URL]
            #expect(onBoard == urls, "every file must come back, not only the first")
            await watcher.tick()
            #expect(try items().count == 1, "pasting the files back must not capture them again")
        }

        @Test("a clip whose files are all gone pastes nothing, leaves the board alone and says why")
        @MainActor
        func whenEveryFileIsGone_thenNothingIsWritten() async throws {
            let urls = try makeFiles(["basil.pdf", "parmesan.txt"])
            await watcher.tick()
            AppPasteboard.general.clearContents()
            AppPasteboard.general.writeObjects(urls as [NSURL])
            await watcher.tick()
            let item = try #require(try items().first)
            for url in urls {
                try FileManager.default.removeItem(at: url)
            }
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("still here", forType: .string)

            var toasts: [StatusToast] = []
            state.showToast = { toasts.append($0) }

            let payload = state.writeItem(item)

            #expect(toasts == [.filesGone], "the shelf is closed by the time a paste is refused, so a toast says why")
            #expect(payload == nil)
            #expect(AppPasteboard.general.string(forType: .string) == "still here")
            #expect(state.lastUserError != nil)
        }

        @Test("a PDF-only copy is captured, gets a thumbnail, and pastes back as the original PDF")
        @MainActor
        func whenOnlyPDFCopied_thenCapturedAndPastesBack() async throws {
            var box = CGRect(x: 0, y: 0, width: 400, height: 200)
            let pdf = NSMutableData()
            let consumer = try #require(CGDataConsumer(data: pdf))
            let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
            context.fill(box)
            context.endPDFPage()
            context.closePDF()
            let flavour = NSPasteboard.PasteboardType("com.adobe.pdf")
            await watcher.tick()
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setData(pdf as Data, forType: flavour)

            await watcher.tick()

            let item = try #require(try items().first)
            #expect(item.type == .image)
            let thumbnail = await ThumbnailService(modelContainer: container).thumbnail(for: item.id, maxPixel: 100)
            #expect(thumbnail != nil, "the card would show an empty placeholder")

            _ = state.writeItem(item)
            #expect(AppPasteboard.general.data(forType: flavour) == pdf as Data, "the original PDF must come back")
        }

        @Test("an SVG-only copy is captured, gets a thumbnail, and pastes back as the original SVG")
        @MainActor
        func whenOnlySVGCopied_thenCapturedAndPastesBack() async throws {
            let svg = Data(
                "<svg xmlns='http://www.w3.org/2000/svg' width='120' height='60'><rect width='120' height='60'/></svg>"
                    .utf8
            )
            let flavour = NSPasteboard.PasteboardType("public.svg-image")
            await watcher.tick()
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setData(svg, forType: flavour)

            await watcher.tick()

            let item = try #require(try items().first)
            #expect(item.type == .image)
            let thumbnail = await ThumbnailService(modelContainer: container).thumbnail(for: item.id, maxPixel: 100)
            #expect(thumbnail != nil, "the card would show an empty placeholder")
            _ = state.writeItem(item)
            #expect(AppPasteboard.general.data(forType: flavour) == svg)
        }

        @Test("SVG copied as text is an SVG code clip that gets a drawing and pastes back as the same text")
        @MainActor
        func whenSVGCopiedAsText_thenCodeClipWithADrawing() async throws {
            let svg =
                "<svg xmlns='http://www.w3.org/2000/svg' width='120' height='60'><rect width='120' height='60'/></svg>"
            await watcher.tick()
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString(svg, forType: .string)

            await watcher.tick()

            let item = try #require(try items().first)
            #expect(item.isSVGSource)
            let thumbnail = await ThumbnailService(modelContainer: container).thumbnail(for: item.id, maxPixel: 100)
            #expect(thumbnail != nil, "the card would show the code instead of the drawing")
            _ = state.writeItem(item)
            #expect(AppPasteboard.general.string(forType: .string) == svg)
        }

        @Test("a concealed copy from a password manager never reaches the store")
        @MainActor
        func whenConcealedMarker_thenNotCaptured() async throws {
            await watcher.tick()
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("hunter2-\(UUID().uuidString)", forType: .string)
            AppPasteboard.general.setData(
                Data(),
                forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            )

            await watcher.tick()

            #expect(try items().isEmpty)
        }
    }

    /// A burst of copies while the UI reads the same store and a save observer is installed. It proves every copy of a
    /// burst arrives. It cannot reproduce the freeze five quick copies once caused (the main thread blocked on the
    /// storage actor while the actor's save waited for it): that guard is `ModelSaveObserverTests`.
    @Suite("A burst of copies", .serialized)
    struct CopyBurstTests {
        @Test("thirty copies while the main actor reads the store all arrive")
        @MainActor
        func whenBurst_thenAllIngested() async throws {
            let container = try ModelContainerSetup.makeInMemory()
            let service = StorageService(modelContainer: container)
            let observer = ModelSaveObserver
                .observe { _ = try? ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()) }
            defer { NotificationCenter.default.removeObserver(observer) }

            let writer = Task {
                for index in 0..<30 {
                    let text = "burst \(index) \(UUID().uuidString)"
                    try await service.ingest(PasteboardCapture(
                        typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                        contentHash: UUID().uuidString
                    ))
                }
            }
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                _ = try ModelContext(container)
                    .fetch(FetchDescriptor<ClipboardItem>()) // the UI reading while saves happen
                if writer.isCancelled { break }
                try await Task.sleep(for: .milliseconds(10))
                if try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>()) >= 30 { break }
            }
            try await writer.value

            #expect(try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>()) == 30)
        }
    }
}

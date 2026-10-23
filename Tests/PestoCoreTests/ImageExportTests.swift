// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Saving an image clip to a file")
struct ImageExportTests {
    private let moment = Date(timeIntervalSince1970: 1_792_000_000)

    @Test("⌘S saves a plain picture and nothing that is covered, hidden, filtered or not yet read")
    func whenCovered_thenTheKeyboardSavesNothing() {
        func allowed(
            image: Bool = true, filtered: Bool = false, hidden: Bool = false, pending: Bool = false,
            shared: Bool = false
        )
        -> Bool {
            ImageExport.keyboardSaveAllowed(
                isImage: image, isFilteredContent: filtered, isHidden: hidden, isPendingAnalysis: pending,
                isCoveredForSharing: shared
            )
        }
        #expect(allowed())
        #expect(!allowed(image: false))
        #expect(!allowed(filtered: true))
        #expect(!allowed(hidden: true))
        #expect(!allowed(pending: true))
        #expect(!allowed(shared: true))
    }

    @Test("the extension follows the stored type, and an unknown type is a PNG")
    func whenTypeIsKnown_thenItsExtension() {
        #expect(ImageExport.fileExtension(forUTI: "public.jpeg") == "jpeg")
        #expect(ImageExport.fileExtension(forUTI: "public.png") == "png")
        #expect(ImageExport.fileExtension(forUTI: "public.svg-image") == "svg")
        #expect(ImageExport.fileExtension(forUTI: "com.example.nothing") == "png")
    }

    @Test("a clip's title names the file, with the characters a file name cannot hold removed")
    func whenTitled_thenTheTitleIsTheName() {
        #expect(ImageExport.baseName(title: "Logo / v2: final", date: moment) == "Logo v2 final")
        #expect(ImageExport.baseName(title: "  .hidden  ", date: moment) == "hidden")
    }

    @Test("with no usable title the name is the date, and a very long title is cut")
    func whenUntitled_thenTheDateIsTheName() {
        let name = ImageExport.baseName(title: nil, date: moment)
        #expect(name.hasPrefix("Pesto picture 20"))
        #expect(ImageExport.baseName(title: "///", date: moment) == name)
        #expect(ImageExport.baseName(title: String(repeating: "a", count: 300), date: moment).count == 60)
    }

    @Test("a name that is taken gets a number, and the first free one is used")
    func whenNameIsTaken_thenNumbered() {
        let folder = URL(fileURLWithPath: "/tmp/exports", isDirectory: true)
        let taken: Set = ["/tmp/exports/Logo.png", "/tmp/exports/Logo 2.png"]
        let url = ImageExport.destination(in: folder, base: "Logo", fileExtension: "png") { taken.contains($0.path) }
        #expect(url.lastPathComponent == "Logo 3.png")
        let free = ImageExport.destination(in: folder, base: "Logo", fileExtension: "jpeg") { taken.contains($0.path) }
        #expect(free.lastPathComponent == "Logo.jpeg")
    }

    @Test("the Downloads folder of a test run is inside its own temporary folder, never the person's")
    func whenNotNormalMode_thenDownloadsIsScoped() {
        let configuration = RuntimeConfiguration(mode: .uiTest, session: "abc", seed: .basic, accessibility: .trusted)
        let folder = AppPaths.downloadsDirectory(
            for: configuration,
            downloads: URL(fileURLWithPath: "/Users/someone/Downloads"),
            applicationSupport: URL(fileURLWithPath: "/Users/someone/Library/Application Support"),
            temporary: URL(fileURLWithPath: "/tmp")
        )
        #expect(!folder.path.hasPrefix("/Users/someone"))
        let normal = AppPaths.downloadsDirectory(
            for: RuntimeConfiguration(mode: .normal, session: "abc", seed: .basic, accessibility: .trusted),
            downloads: URL(fileURLWithPath: "/Users/someone/Downloads"),
            applicationSupport: URL(fileURLWithPath: "/x"),
            temporary: URL(fileURLWithPath: "/tmp")
        )
        #expect(normal.path == "/Users/someone/Downloads")
    }

    @Test("Save Image uses the chosen folder while it exists, and falls back to Downloads saying so when it is gone")
    func whenFolderChosen_thenItIsUsedOrFallsBack() {
        let downloads = URL(fileURLWithPath: "/Users/x/Downloads", isDirectory: true)
        let none = ImageExport.saveFolder(chosenPath: "", downloads: downloads) { _ in false }
        #expect(none.folder == downloads && !none.usedFallback)
        let good = ImageExport.saveFolder(chosenPath: "/Users/x/Pictures/Clips", downloads: downloads) { _ in true }
        #expect(good.folder.path == "/Users/x/Pictures/Clips" && !good.usedFallback)
        let gone = ImageExport.saveFolder(chosenPath: "/Volumes/Gone", downloads: downloads) { _ in false }
        #expect(gone.folder == downloads && gone.usedFallback)
    }
}

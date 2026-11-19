// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

@Suite("Quick-insert Batch 4A: pictures, metadata, sizes and accents")
@MainActor
struct QuickInsertBatch4ATests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    private func makePNG(width: Int = 60, height: Int = 40) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func makeGIF(frames: Int = 2) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames, nil)
        )
        for index in 0..<frames {
            let context = try #require(CGContext(
                data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: Double(index) * 0.5, green: 0.4, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            let image = try #require(context.makeImage())
            CGImageDestinationAddImage(destination, image, nil)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("Setting.keyboardSize defaults to medium")
    func whenKeyboardSizeDefaultChecked_thenMedium() {
        #expect(Setting.keyboardSize.defaultValue == KeyboardSize.medium.rawValue)
    }

    @Test("QuickInsertSet, QuickInsertEntry and QuickInsertCollection carry new fields and decode legacy payloads")
    func whenLegacyJSONDecoded_thenDefaultsAreApplied() throws {
        let id = UUID()
        let colID = UUID()
        let legacyJSON = """
        {
          "createdAt": 0,
          "entries": [{
            "id": "\(id.uuidString)",
            "section": "recent",
            "kind": "text",
            "title": "Hello",
            "text": "Hello",
            "expandsOnInsert": false
          }],
          "collections": [{
            "id": "\(colID.uuidString)",
            "name": "Work",
            "symbolName": "briefcase",
            "entryIDs": ["\(id.uuidString)"]
          }],
          "returnsAfterInsert": true
        }
        """
        let decoded = try JSONDecoder().decode(QuickInsertSet.self, from: Data(legacyJSON.utf8))
        #expect(decoded.keyboardSize == .medium)
        #expect(decoded.accent == .brand)
        #expect(decoded.collections.first?.color == "")
        let entry = try #require(decoded.entries.first)
        #expect(entry.source == nil)
        #expect(entry.sourceIsThisDevice == false)
        #expect(entry.thumbnail == nil)
        #expect(entry.recognizedText == nil)
        #expect(entry.hasRecognizedText == false)
        #expect(entry.isAnimated == false)
    }

    @Test("image items without OCR text are included with a <= 24 KB thumbnail; GIFs take first frame")
    func whenImageWithoutOCR_thenIncludedWithThumbnail() throws {
        let context = try ModelContext(ModelContainerSetup.makeInMemory())
        let png = try makePNG()
        let gif = try makeGIF()

        let imgItem = ClipboardItem(
            type: .image, previewText: "", contentHash: "img1", byteSize: png.count,
            deviceID: "d", sequenceNumber: 1
        )
        imgItem.timestamp = Date(timeIntervalSince1970: 1_800_000_100)
        imgItem.customTitle = "Screenshot"
        context.insert(imgItem)

        let gifItem = ClipboardItem(
            type: .image, previewText: "", contentHash: "gif1", byteSize: gif.count,
            deviceID: "d", sequenceNumber: 2
        )
        gifItem.timestamp = Date(timeIntervalSince1970: 1_800_000_200)
        context.insert(gifItem)

        let blobs: [UUID: Data] = [imgItem.id: png, gifItem.id: gif]
        let set = try QuickInsertSelection.set(
            in: context,
            now: Date(timeIntervalSince1970: 1_800_000_300),
            options: .init(keyboardSize: .large, accent: .brand),
            reader: .init(
                text: { _ in nil },
                thumbnail: { item in
                    blobs[item.id].flatMap {
                        ImageDownsampler.thumbnailJPEG(
                            from: $0, maxPixel: QuickInsertPolicy.thumbnailMaxPixel,
                            maxBytes: QuickInsertPolicy.maxThumbnailBytes
                        )
                    }
                },
                recognizedText: { _ in nil },
                source: { _ in ("Photos", false) },
                isAnimated: { $0.id == gifItem.id }
            )
        )

        #expect(set.keyboardSize == .large)
        #expect(set.entries.count == 2)
        let gifEntry = try #require(set.entries.first { $0.id == gifItem.id })
        #expect(gifEntry.isAnimated == true)
        #expect((gifEntry.thumbnail?.count ?? 0) > 0)
        #expect((gifEntry.thumbnail?.count ?? Int.max) <= QuickInsertPolicy.maxThumbnailBytes)
        #expect(gifEntry.hasRecognizedText == false)
        #expect(gifEntry.source == "Photos")
        #expect(gifEntry.sourceIsThisDevice == false)

        let imgEntry = try #require(set.entries.first { $0.id == imgItem.id })
        #expect(imgEntry.customTitle == "Screenshot")
        #expect(imgEntry.isAnimated == false)
    }

    @Test("image items with secret OCR text are excluded; non-secret OCR text is included and searchable")
    func whenImageHasOCR_thenSecretExcludedAndSafeIncluded() throws {
        let context = try ModelContext(ModelContainerSetup.makeInMemory())
        let png = try makePNG()

        let safeImage = ClipboardItem(
            type: .image, previewText: "", contentHash: "safe", byteSize: png.count,
            deviceID: "d", sequenceNumber: 1
        )
        safeImage.timestamp = Date(timeIntervalSince1970: 1_800_000_100)
        context.insert(safeImage)

        let secretImage = ClipboardItem(
            type: .image, previewText: "", contentHash: "sec", byteSize: png.count,
            deviceID: "d", sequenceNumber: 2
        )
        secretImage.timestamp = Date(timeIntervalSince1970: 1_800_000_200)
        context.insert(secretImage)

        let ocrMap: [UUID: String] = [
            safeImage.id: "Wi-Fi Guest Pass",
            secretImage.id: "Token: \(secret)"
        ]
        let thumb = try #require(ImageDownsampler.thumbnailJPEG(
            from: png, maxPixel: QuickInsertPolicy.thumbnailMaxPixel, maxBytes: QuickInsertPolicy.maxThumbnailBytes
        ))

        let set = try QuickInsertSelection.set(
            in: context,
            now: Date(timeIntervalSince1970: 1_800_000_300),
            reader: .init(
                text: { _ in nil },
                thumbnail: { _ in thumb },
                recognizedText: { ocrMap[$0.id] },
                source: { _ in ("iPhone", true) }
            )
        )

        #expect(set.entries.map(\.id) == [safeImage.id])
        let entry = try #require(set.entries.first)
        #expect(entry.hasRecognizedText == true)
        #expect(entry.recognizedText == "Wi-Fi Guest Pass")
        #expect(entry.sourceIsThisDevice == true)

        let menu = KeyboardMenu(hasFullAccess: true) { set }
        #expect(menu.entries(matching: "Guest").map(\.id) == [safeImage.id])

        // AutoFill (QuickInsertMenu) excludes image-only entries.
        let autoFill = QuickInsertMenu(set: set)
        #expect(autoFill.groups(matching: "").isEmpty)
    }

    @Test("collection color is carried in QuickInsertCollection")
    func whenCollectionIncluded_thenColorIsCarried() throws {
        let context = try ModelContext(ModelContainerSetup.makeInMemory())
        let board = try Pinboard(name: "Design", symbolName: "paintbrush", colorHex: "#D94F70", sortOrder: 0)
        context.insert(board)
        let item = ClipboardItem(
            type: .text, previewText: "Hex", contentHash: "h1", byteSize: 3, deviceID: "d", sequenceNumber: 1
        )
        item.collectionID = board.id
        context.insert(item)

        let set = try QuickInsertSelection.set(
            in: context, now: .now, options: .init(collectionIDs: [board.id]),
            text: { _ in "Hex" }
        )

        #expect(set.collections.first?.color == "#D94F70")
    }
}

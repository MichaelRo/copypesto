// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

@Suite("iOS Library draws every card kind in light and dark")
@MainActor
struct LibraryCardRenderingTests {
    private static let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/library-renders", isDirectory: true)

    private static let cardSize = CGSize(width: 174, height: 156)

    private func sampleImage(width: CGFloat = 240, height: CGFloat = 180) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor(red: 0.25, green: 0.55, blue: 0.35, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor(red: 0.95, green: 0.78, blue: 0.25, alpha: 1).setFill()
            let side = min(width, height) * 0.5
            context.cgContext.fillEllipse(in: CGRect(
                x: (width - side) / 2,
                y: (height - side) / 2,
                width: side,
                height: side
            ))
        }
    }

    private func makeItem(
        in context: ModelContext,
        type: ClipboardType,
        preview: String,
        title: String? = nil,
        sensitivity: SensitivityCategory? = nil,
        maskedPreview: String? = nil
    ) -> ClipboardItem {
        let item = ClipboardItem(
            type: type,
            previewText: sensitivity != nil ? (maskedPreview ?? preview) : preview,
            sensitivity: sensitivity,
            sensitivityMaskedPreview: maskedPreview,
            contentHash: UUID().uuidString,
            byteSize: max(preview.utf8.count, 1024),
            deviceID: "test-device",
            sequenceNumber: 1
        )
        item.customTitle = title
        item.sourceAppName = "Notes"
        context.insert(item)
        return item
    }

    private func render(
        item: ClipboardItem,
        face: PestoMobile.CardFace,
        media: CardMediaState,
        inCollection: Bool,
        appState: MobileAppState,
        dark: Bool,
        name: String
    ) throws -> Data {
        let shape = RoundedRectangle(cornerRadius: CardGridLayout.cornerRadius, style: .continuous)
        let view = ClipCardFace(
            item: item,
            face: face,
            media: media,
            width: Self.cardSize.width,
            revision: ClipCard.Revision(item),
            inCollection: inCollection
        )
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(dark ? Color.white.opacity(0.10) : Color.white)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
        }
        .padding(12)
        .background(dark ? Color.black : Color(white: 0.92))
        .environment(appState)
        .environment(\.colorScheme, dark ? .dark : .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        #expect(image.size == CGSize(width: Self.cardSize.width + 24, height: Self.cardSize.height + 24), "\(name)")
        let data = try #require(image.pngData())
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        try data.write(to: Self.output.appendingPathComponent("\(name).png"))
        return data
    }

    @Test("all 10 card kinds and states render in light and dark")
    func whenAllCardKindsRendered_thenLightAndDarkDiffer() async throws {
        let library = try await MobileTestLibrary()
        let context = try ModelContext(ModelContainerSetup.makeInMemory())
        let pic = sampleImage()

        let cases: [(name: String, item: ClipboardItem, face: PestoMobile.CardFace, media: CardMediaState, inCollection: Bool)] = [
            (
                "text",
                makeItem(in: context, type: .text, preview: "Pick up basil, pine nuts and parmesan on the way home"),
                PestoMobile.CardFace.decide(.init(
                    type: .text, text: "Pick up basil, pine nuts and parmesan on the way home", isConcealed: false
                )),
                CardMediaState(),
                false
            ),
            (
                "titled",
                makeItem(in: context, type: .text, preview: "12 Basil Lane, Apt 4B", title: "Home Address"),
                PestoMobile.CardFace.decide(.init(type: .text, text: "12 Basil Lane, Apt 4B", isConcealed: false)),
                CardMediaState(),
                true
            ),
            (
                "link",
                makeItem(in: context, type: .url, preview: "https://copypesto.net/guide/sync"),
                PestoMobile.CardFace.decide(.init(
                    type: .url, text: "https://copypesto.net/guide/sync", isConcealed: false
                )),
                CardMediaState(),
                false
            ),
            (
                "code",
                makeItem(in: context, type: .code, preview: "let pesto = basil + garlic + oil"),
                PestoMobile.CardFace.decide(.init(
                    type: .code, text: "let pesto = basil + garlic + oil", isConcealed: false
                )),
                CardMediaState(),
                false
            ),
            (
                "color",
                makeItem(in: context, type: .color, preview: "#2F7A49"),
                PestoMobile.CardFace.decide(.init(type: .color, text: "#2F7A49", isConcealed: false)),
                CardMediaState(),
                false
            ),
            (
                "snippet",
                makeItem(in: context, type: .text, preview: "Thanks, {{date}}"),
                PestoMobile.CardFace.decide(.init(type: .text, text: "Thanks, {{date}}", isConcealed: false)),
                CardMediaState(),
                false
            ),
            (
                "picture",
                makeItem(in: context, type: .image, preview: ""),
                PestoMobile.CardFace.decide(.init(type: .image, text: "", isConcealed: false, pictureAspect: 1.0)),
                CardMediaState(picture: .init(image: pic, isAnimated: false)),
                false
            ),
            (
                "gif",
                makeItem(in: context, type: .image, preview: ""),
                PestoMobile.CardFace.decide(.init(
                    type: .image, text: "", isConcealed: false, pictureAspect: 1.0, isAnimated: true
                )),
                CardMediaState(picture: .init(image: pic, isAnimated: true)),
                false
            ),
            (
                "file",
                makeItem(in: context, type: .file, preview: "file:///Users/me/recipe.pdf"),
                PestoMobile.CardFace.decide(.init(
                    type: .file, text: "file:///Users/me/recipe.pdf", isConcealed: false
                )),
                CardMediaState(),
                false
            ),
            (
                "secret-covered",
                makeItem(
                    in: context, type: .text, preview: "sk-proj-abc123",
                    sensitivity: .apiKey, maskedPreview: "sk-proj-••••••••"
                ),
                PestoMobile.CardFace.decide(.init(
                    type: .text, text: "sk-proj-••••••••", isConcealed: true, isSecret: true
                )),
                CardMediaState(),
                false
            ),
            (
                "privacy-covered",
                makeItem(in: context, type: .color, preview: "#2F7A49"),
                PestoMobile.CardFace.decide(.init(type: .color, text: "#2F7A49", isConcealed: true)),
                CardMediaState(),
                false
            )
        ]

        for entry in cases {
            let light = try render(
                item: entry.item, face: entry.face, media: entry.media,
                inCollection: entry.inCollection, appState: library.state, dark: false,
                name: "\(entry.name)-light"
            )
            let dark = try render(
                item: entry.item, face: entry.face, media: entry.media,
                inCollection: entry.inCollection, appState: library.state, dark: true,
                name: "\(entry.name)-dark"
            )
            #expect(light != dark, "\(entry.name) should differ between light and dark")
        }
    }
}

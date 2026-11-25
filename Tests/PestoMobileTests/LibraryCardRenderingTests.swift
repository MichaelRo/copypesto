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
    )
    -> ClipboardItem {
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
        // Mail's sampled color, so every text card renders with the foot glow (ADR 0068).
        item.sourceDominantColorHex = "#0B8BFD"
        context.insert(item)
        return item
    }

    @MainActor
    private struct RenderCase {
        var name: String
        let item: ClipboardItem
        let face: PestoMobile.CardFace
        var media = CardMediaState()
        var inCollection = false
    }

    private func render(_ entry: RenderCase, appState: MobileAppState, dark: Bool) throws -> Data {
        let shape = RoundedRectangle(cornerRadius: CardGridLayout.cornerRadius, style: .continuous)
        let view = ClipCardFace(
            item: entry.item,
            face: entry.face,
            media: entry.media,
            width: Self.cardSize.width,
            revision: ClipCard.Revision(entry.item),
            inCollection: entry.inCollection
        )
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background {
            ZStack {
                dark ? Color.white.opacity(0.10) : Color.white
                if PestoMobile.CardGlowLayer.shows(on: entry.face) {
                    PestoMobile.CardGlowLayer(glow: ClipCard.glow(
                        for: entry.item, apps: nil, isDark: dark, increaseContrast: false, isSelected: false
                    ))
                }
            }
        }
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
        #expect(
            image.size == CGSize(width: Self.cardSize.width + 24, height: Self.cardSize.height + 24),
            "\(entry.name)"
        )
        let data = try RenderedImage.pixels(image)
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        RenderedImage.saveForReview(image, to: Self.output.appendingPathComponent("\(entry.name).png"))
        return data
    }

    private func sampleCases(in context: ModelContext, pic: UIImage) -> [RenderCase] {
        textCases(in: context) + mediaAndCoveredCases(in: context, pic: pic)
    }

    private func textCases(in context: ModelContext) -> [RenderCase] {
        [
            RenderCase(
                name: "text",
                item: makeItem(
                    in: context,
                    type: .text,
                    preview: "Pick up basil, pine nuts and parmesan on the way home"
                ),
                face: PestoMobile.CardFace.decide(.init(
                    type: .text, text: "Pick up basil, pine nuts and parmesan on the way home", isConcealed: false
                ))
            ),
            RenderCase(
                name: "titled",
                item: makeItem(in: context, type: .text, preview: "12 Basil Lane, Apt 4B", title: "Home Address"),
                face: PestoMobile.CardFace.decide(.init(
                    type: .text,
                    text: "12 Basil Lane, Apt 4B",
                    isConcealed: false
                )),
                inCollection: true
            ),
            RenderCase(
                name: "link",
                item: makeItem(in: context, type: .url, preview: "https://copypesto.net/guide/sync"),
                face: PestoMobile.CardFace.decide(.init(
                    type: .url, text: "https://copypesto.net/guide/sync", isConcealed: false
                ))
            ),
            RenderCase(
                name: "code",
                item: makeItem(in: context, type: .code, preview: "let pesto = basil + garlic + oil"),
                face: PestoMobile.CardFace.decide(.init(
                    type: .code, text: "let pesto = basil + garlic + oil", isConcealed: false
                ))
            ),
            RenderCase(
                name: "color",
                item: makeItem(in: context, type: .color, preview: "#2F7A49"),
                face: PestoMobile.CardFace.decide(.init(type: .color, text: "#2F7A49", isConcealed: false))
            ),
            RenderCase(
                name: "snippet",
                item: makeItem(in: context, type: .text, preview: "Thanks, {{date}}"),
                face: PestoMobile.CardFace.decide(.init(type: .text, text: "Thanks, {{date}}", isConcealed: false))
            )
        ]
    }

    private func mediaAndCoveredCases(in context: ModelContext, pic: UIImage) -> [RenderCase] {
        [
            RenderCase(
                name: "picture",
                item: makeItem(in: context, type: .image, preview: ""),
                face: PestoMobile.CardFace.decide(.init(
                    type: .image,
                    text: "",
                    isConcealed: false,
                    pictureAspect: 1.0
                )),
                media: CardMediaState(picture: .init(image: pic, isAnimated: false))
            ),
            RenderCase(
                name: "gif",
                item: makeItem(in: context, type: .image, preview: ""),
                face: PestoMobile.CardFace.decide(.init(
                    type: .image, text: "", isConcealed: false, pictureAspect: 1.0, isAnimated: true
                )),
                media: CardMediaState(picture: .init(image: pic, isAnimated: true))
            ),
            RenderCase(
                name: "file",
                item: makeItem(in: context, type: .file, preview: "file:///Users/me/recipe.pdf"),
                face: PestoMobile.CardFace.decide(.init(
                    type: .file, text: "file:///Users/me/recipe.pdf", isConcealed: false
                ))
            ),
            RenderCase(
                name: "secret-covered",
                item: makeItem(
                    in: context, type: .text, preview: "sk-proj-abc123",
                    sensitivity: .apiKey, maskedPreview: "sk-proj-••••••••"
                ),
                face: PestoMobile.CardFace.decide(.init(
                    type: .text, text: "sk-proj-••••••••", isConcealed: true, isSecret: true
                ))
            ),
            RenderCase(
                name: "privacy-covered",
                item: makeItem(in: context, type: .color, preview: "#2F7A49"),
                face: PestoMobile.CardFace.decide(.init(type: .color, text: "#2F7A49", isConcealed: true))
            )
        ]
    }

    @Test("all 10 card kinds and states render in light and dark")
    func whenAllCardKindsRendered_thenLightAndDarkDiffer() async throws {
        let library = try await MobileTestLibrary()
        let context = try ModelContext(ModelContainerSetup.makeInMemory())
        let cases = sampleCases(in: context, pic: sampleImage())

        for entry in cases {
            var lightCase = entry
            lightCase.name = "\(entry.name)-light"
            var darkCase = entry
            darkCase.name = "\(entry.name)-dark"
            let light = try render(lightCase, appState: library.state, dark: false)
            let dark = try render(darkCase, appState: library.state, dark: true)
            #expect(light != dark, "\(entry.name) should differ between light and dark")
        }
    }
}

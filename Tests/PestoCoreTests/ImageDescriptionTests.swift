// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
#if canImport(FoundationModels)
    import FoundationModels
#endif
@testable import PestoCore

@Suite("On-device image description")
struct ImageDescriptionTests {
    @Test("text actions are offered for text and code, never the image action")
    func whenText_thenTextActionsOnly() {
        for type in [ClipboardType.text, .code] {
            #expect(AIAction.actions(for: type) == AIAction.textActions)
        }
    }

    @Test("other types have no AI actions")
    func whenOtherType_thenNone() {
        for type in [ClipboardType.url, .file, .color] {
            #expect(AIAction.actions(for: type).isEmpty)
        }
    }

    @Test("bytes that are not an image are refused before the model is asked")
    func whenNotAnImage_thenInvalidImage() async {
        guard #available(macOS 27, *) else { return }
        await #expect(throws: AppleIntelligenceClient.ClientError.invalidImage) {
            try await AppleIntelligenceClient().describe(imageData: Data("not an image".utf8))
        }
    }

    @Test("the real on-device model describes a picture", .enabled(if: Self.modelCanSee))
    func whenModelCanSee_thenDescribes() async throws {
        guard #available(macOS 27, *) else { return }
        let description = try await AppleIntelligenceClient().describe(imageData: Self.redSquarePNG())
        #expect(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    static var modelCanSee: Bool {
        #if canImport(FoundationModels) && compiler(>=6.4)
            guard #available(macOS 27, *) else { return false }
            let model = SystemLanguageModel.default
            return model.availability == .available && model.capabilities.contains(.vision)
        #else
            return false
        #endif
    }

    private static func redSquarePNG() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

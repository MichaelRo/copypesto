// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
#if canImport(FoundationModels) && compiler(>=6.4)
    import FoundationModels
#endif
@testable import PestoCore

@Suite("On-device image screening")
struct ImageScreeningTests {
    #if canImport(FoundationModels) && compiler(>=6.4)
        @available(macOS 27, *)
        @Test("a guardrail stop or a refusal from the model means the image is sensitive")
        func whenModelStops_thenSensitive() {
            let guardrail = LanguageModelError.guardrailViolation(.init(debugDescription: "unsafe"))
            let refusal = LanguageModelError.refusal(.init(explanation: "declined", debugDescription: "declined"))
            #expect(OnDeviceImageScreener.isSafetyStop(guardrail))
            #expect(OnDeviceImageScreener.isSafetyStop(refusal))
        }

        @available(macOS 27, *)
        @Test("other model errors are not evidence about the image")
        func whenOtherError_thenNotSensitive() {
            let tooBig = LanguageModelError.contextSizeExceeded(.init(
                contextSize: 100,
                tokenCount: 200,
                debugDescription: "too long"
            ))
            #expect(!OnDeviceImageScreener.isSafetyStop(tooBig))
            #expect(!OnDeviceImageScreener.isSafetyStop(URLError(.timedOut)))
        }
    #endif

    @Test("the description Apple gives for a guardrail stop is recognised even from an unknown error type")
    func whenDescriptionMentionsGuardrails_thenSensitive() {
        struct Stop: LocalizedError { var errorDescription: String? {
            "The model's safety guardrails were triggered."
        }
        }
        #expect(OnDeviceImageScreener.isSafetyStop(Stop()))
    }

    @Test("bytes that are not an image are never called sensitive")
    func whenNotAnImage_thenFalse() async {
        #expect(await OnDeviceImageScreener().isSensitive(imageData: Data("not an image".utf8)) == false)
    }

    @Test("an ordinary picture is not flagged by the real model", .enabled(if: ImageDescriptionTests.modelCanSee))
    func whenBenignPicture_thenNotSensitive() async throws {
        let context = try #require(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1))
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

        #expect(await OnDeviceImageScreener().isSensitive(imageData: output as Data) == false)
    }
}

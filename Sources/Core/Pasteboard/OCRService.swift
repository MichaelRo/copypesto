// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import os
import Vision

/// On-device text extraction from image clipboard items using Apple Vision.
///
/// Runs on a detached task so the model actor is never blocked during ingest.
/// No data leaves the device — VNRecognizeTextRequest is fully local.
public protocol TextRecognizing: Sendable {
    func recognize(imageData: Data) async -> String?
}

public struct OCRService: TextRecognizing {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "OCR")

    public init() {}

    /// Runs the recognizer once on a blank image so the model is loaded before the first real screenshot; that first
    /// run can take many seconds, and a clip does not appear until it has been read (secrets in it are masked).
    public func prewarm() async {
        let size = 16
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else { return }
        let output = NSMutableData()
        let png = "public.png" as CFString
        guard let destination = CGImageDestinationCreateWithData(output, png, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        _ = await recognize(imageData: output as Data)
    }

    /// Extracts printed text from image data. Returns nil when the image contains
    /// no recognizable text or cannot be decoded.
    public func recognize(imageData: Data) async -> String? {
        await Task.detached(priority: .utility) {
            guard
                let source = CGImageSourceCreateWithData(
                    imageData as CFData,
                    [kCGImageSourceShouldCache: false] as CFDictionary
                ),
                let cgImage = ImageDownsampler.boundedImage(from: source) else { return nil }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            // A failed read is logged, not treated as "no text": a picture whose text could not be read is not a
            // picture
            // known to hold no secret.
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                Self.logger.error("Text recognition failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }

            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.value
    }
}

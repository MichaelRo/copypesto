// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import os
import Synchronization
import Vision

/// On-device QR and barcode detection for image clips using Apple Vision.
/// Runs locally with no network access and caches results per clip ID/hash in memory only while the app runs.
public enum BarcodeDetector {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Barcode")
    private static let queue = DispatchQueue(label: "\(AppIdentity.logSubsystem).barcode", qos: .utility)

    private struct CacheKey: Hashable {
        let id: UUID
        let contentHash: String
    }

    private static let cache = Mutex<[CacheKey: [BarcodePayload]]>([:])

    private static let supportedSymbologies: [VNBarcodeSymbology] = [
        .qr,
        .microQR,
        .aztec,
        .pdf417,
        .dataMatrix,
        .ean13,
        .ean8,
        .upce,
        .code128,
        .code39,
        .code93,
        .i2of5,
        .codabar,
        .gs1DataBar
    ]

    public static func detect(in imageData: Data) async -> [BarcodePayload] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: detectSync(in: imageData))
            }
        }
    }

    public static func cachedOrDetect(id: UUID, contentHash: String, imageData: () -> Data?) -> [BarcodePayload] {
        let key = CacheKey(id: id, contentHash: contentHash)
        if let hit = cache.withLock({ $0[key] }) { return hit }
        guard let data = imageData() else { return [] }
        let detected = detectSync(in: data)
        cache.withLock { store in
            if store.count > 128 { store.removeAll() }
            store[key] = detected
        }
        return detected
    }

    public static func detectSync(in imageData: Data) -> [BarcodePayload] {
        guard !OCRService.isDisabled(environment: ProcessInfo.processInfo.environment),
              let source = CGImageSourceCreateWithData(
                  imageData as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let cgImage = ImageDownsampler.boundedImage(from: source) else
        {
            return []
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = supportedSymbologies

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            logger.error("Barcode detection failed: \(error.localizedDescription, privacy: .public)")
            return []
        }

        var seen = Set<String>()
        var results: [BarcodePayload] = []
        for observation in request.results ?? [] {
            guard let raw = observation.payloadStringValue else { continue }
            let kind = Self.kind(for: observation.symbology)
            guard let payload = BarcodePayload(rawValue: raw, kind: kind),
                  seen.insert(payload.rawValue).inserted else { continue }
            results.append(payload)
        }
        return results
    }

    public static func clearCache() {
        cache.withLock { $0.removeAll() }
    }

    private static func kind(for symbology: VNBarcodeSymbology) -> BarcodePayload.Kind {
        switch symbology {
        case .qr, .microQR: .qr
        case .aztec: .aztec
        case .pdf417, .microPDF417: .pdf417
        case .dataMatrix: .dataMatrix
        default: .barcode
        }
    }
}

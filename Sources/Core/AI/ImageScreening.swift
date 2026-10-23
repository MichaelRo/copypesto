// SPDX-License-Identifier: MIT
import Foundation
#if canImport(FoundationModels) && compiler(>=6.4)
    import FoundationModels
#endif

public protocol ImageSensitivityScreening: Sendable {
    func isSensitive(imageData: Data) async -> Bool
}

/// Best-effort screening with Apple's on-device model, used when the user has content filtering on. The model's
/// safety guardrails refuse explicit pictures, and that refusal is the signal: nothing is generated, stored or sent
/// anywhere. Without a Mac that runs the vision model it never flags anything, and it can miss things a person would
/// flag, so any card can also be marked by hand.
public struct OnDeviceImageScreener: ImageSensitivityScreening {
    static let maxPixel = 768

    public init() {}

    public func isSensitive(imageData: Data) async -> Bool {
        guard #available(macOS 27, *), AppleIntelligenceClient.supportsVision,
              let small = ImageDownsampler.thumbnailPNG(from: imageData, maxPixel: Self.maxPixel) else { return false }
        do {
            try await AppleIntelligenceClient().screen(imageData: small)
            return false
        } catch {
            return Self.isSafetyStop(error)
        }
    }

    /// True for the model declining or tripping its guardrails; any other failure says nothing about the picture.
    static func isSafetyStop(_ error: any Error) -> Bool {
        #if canImport(FoundationModels) && compiler(>=6.4)
            if #available(macOS 27, *), let modelError = error as? LanguageModelError {
                switch modelError {
                case .guardrailViolation, .refusal: return true
                default: break
                }
            }
        #endif
        // The earlier error type of the same framework reads "The model's safety guardrails were triggered."
        return (error as? any LocalizedError)?.errorDescription?.localizedCaseInsensitiveContains("guardrail") == true
    }
}

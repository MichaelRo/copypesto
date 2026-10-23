// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// On-device AI via Apple's Foundation Models framework (macOS 26+, Apple Silicon).
///
/// Uses `SystemLanguageModel.default` with a per-call `LanguageModelSession` so each
/// AI action is a fresh, single-turn conversation. No history is retained between calls.
public struct AppleIntelligenceClient: Sendable {
    public enum ClientError: Error, LocalizedError, Equatable {
        case unavailable
        case turnedOff
        case modelUnavailable(String)
        case visionUnavailable
        case invalidImage
        case tooLong

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                "Apple Intelligence requires macOS 26 or later."
            case .turnedOff:
                "Turned off in Pesto\u{2019}s settings."
            case .visionUnavailable:
                "This Mac\u{2019}s on-device model can\u{2019}t read pictures."
            case .invalidImage:
                "That picture couldn\u{2019}t be read."
            case .tooLong:
                "That text is too long for the on-device model."
            case let .modelUnavailable(reason):
                // swiftlint:disable:next line_length
                "Apple Intelligence is not available: \(reason). Enable it in System Settings → Apple Intelligence & Siri."
            }
        }
    }

    public init() {}

    @available(macOS 26, *)
    public func complete(system: String, userMessage: String) async throws -> String {
        #if canImport(FoundationModels)
            guard AIAvailability.isUserEnabled() else { throw ClientError.turnedOff }
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                let reason = if case let .unavailable(r) = model.availability {
                    switch r {
                    case .deviceNotEligible: "device not eligible"
                    case .appleIntelligenceNotEnabled: "Apple Intelligence not enabled"
                    case .modelNotReady: "model not ready"
                    @unknown default: "unknown reason"
                    }
                } else {
                    "unknown"
                }
                throw ClientError.modelUnavailable(reason)
            }
            let session = LanguageModelSession(model: model, instructions: system)
            do {
                return try await session.respond(to: userMessage).content
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                throw ClientError.tooLong
            }
        #else
            throw ClientError.unavailable
        #endif
    }

    /// The model's window in tokens, or nil where it cannot be asked (before macOS 26).
    public static var contextTokens: Int? {
        #if canImport(FoundationModels)
            guard #available(macOS 26, *) else { return nil }
            return SystemLanguageModel.default.contextSize
        #else
            return nil
        #endif
    }

    /// Whether the on-device model is ready and can read images. Cheap; call it when building a menu.
    public static var supportsVision: Bool {
        #if canImport(FoundationModels) && compiler(>=6.4) // image input needs the macOS 27 SDK
            guard #available(macOS 27, *), AIAvailability.isUserEnabled() else { return false }
            let model = SystemLanguageModel.default
            return model.availability == .available && model.capabilities.contains(.vision)
        #else
            return false
        #endif
    }

    @available(macOS 27, *)
    public func describe(imageData: Data) async throws -> String {
        #if canImport(FoundationModels) && compiler(>=6.4) // image input needs the macOS 27 SDK
            try await respond(
                to: imageData,
                instructions: AIAction.describeImage.systemPrompt,
                prompt: "Describe this image."
            )
        #else
            throw ClientError.unavailable
        #endif
    }

    /// Loads the model ahead of the first picture, so the first screening does not pay for the cold start.
    public static func prewarmVision() {
        #if canImport(FoundationModels) && compiler(>=6.4)
            guard #available(macOS 27, *), supportsVision else { return }
            LanguageModelSession(model: .default, instructions: "Answer with the single word OK.").prewarm()
        #endif
    }

    /// Shows the picture to the model with a trivial request. Whatever it says is ignored: what matters is whether the
    /// model's safety guardrails stop it, which is thrown to the caller.
    @available(macOS 27, *)
    public func screen(imageData: Data) async throws {
        #if canImport(FoundationModels) && compiler(>=6.4)
            _ = try await respond(to: imageData, instructions: "Answer with the single word OK.", prompt: "Reply OK.")
        #else
            throw ClientError.unavailable
        #endif
    }

    #if canImport(FoundationModels) && compiler(>=6.4)
        @available(macOS 27, *)
        private func respond(to imageData: Data, instructions: String, prompt: String) async throws -> String {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ClientError.invalidImage }
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { throw ClientError.modelUnavailable("not ready") }
            guard model.capabilities.contains(.vision) else { throw ClientError.visionUnavailable }
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: Prompt {
                prompt
                Attachment(image)
            })
            return response.content
        }
    #endif
}

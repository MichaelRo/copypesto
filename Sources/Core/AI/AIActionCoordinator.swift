// SPDX-License-Identifier: MIT
import Foundation

/// Result of a completed AI action, ready for display in the result panel.
public struct AIResult: Sendable, Identifiable {
    public let id: UUID
    public let action: AIAction
    /// Truncated preview of the source text (for display only).
    public let sourcePreview: String
    /// The model's response, or an error message if the call failed.
    public let result: String
    public let isError: Bool
    /// How much of the clip the model read; nil for a picture or an error.
    public let coverage: Coverage?
    /// The clip the answer was made from, so pasting the answer can count as using it.
    public let sourceItemID: UUID?
    /// True when the answer came from a secret the person had shown; pasting it keeps it off Universal Clipboard.
    public let isProtected: Bool
    /// Set when a long text is read a part at a time: what has been read and what is next.
    public let progress: Progress?

    /// A text read one part at a time: the answers so far and what the panel offers next.
    public struct Progress: Sendable, Equatable {
        public let answers: [AIPartAnswer]
        public let partCount: Int
        public let totalCharacters: Int
        public let readableCharacters: Int
        public let next: AIPartNext?
        public let isReading: Bool
        public let isCombining: Bool
        /// Why the part that was asked for failed; the answers before it are kept.
        public let failure: String?
        public let hasCombined: Bool

        public var isCut: Bool {
            readableCharacters < totalCharacters
        }
    }

    public struct Coverage: Sendable, Equatable {
        public let shown: Int
        public let total: Int

        public init(shown: Int, total: Int) {
            self.shown = shown
            self.total = total
        }

        public var isPartial: Bool {
            shown < total
        }
    }

    public init(
        action: AIAction, sourcePreview: String, result: String, isError: Bool = false, coverage: Coverage? = nil,
        isProtected: Bool = false, sourceItemID: UUID? = nil, progress: Progress? = nil, id: UUID = UUID()
    ) {
        self.id = id
        self.action = action
        self.sourcePreview = sourcePreview
        self.result = result
        self.isError = isError
        self.coverage = coverage
        self.isProtected = isProtected
        self.sourceItemID = sourceItemID
        self.progress = progress
    }

    public var canPaste: Bool {
        !isError && !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func protecting(_ isProtected: Bool) -> AIResult {
        AIResult(
            action: action, sourcePreview: sourcePreview, result: result, isError: isError, coverage: coverage,
            isProtected: isProtected, sourceItemID: sourceItemID, progress: progress, id: id
        )
    }

    public func madeFrom(_ itemID: UUID?) -> AIResult {
        AIResult(
            action: action, sourcePreview: sourcePreview, result: result, isError: isError, coverage: coverage,
            isProtected: isProtected, sourceItemID: itemID, progress: progress, id: id
        )
    }

    /// The same answer panel with a new text and progress (the next part came in, or a failure).
    public func with(result: String, progress: Progress?) -> AIResult {
        AIResult(
            action: action, sourcePreview: sourcePreview, result: result, isError: isError, coverage: coverage,
            isProtected: isProtected, sourceItemID: sourceItemID, progress: progress, id: id
        )
    }
}

/// Runs one AI action on the on-device model. Nothing here touches the network.
public struct AIActionCoordinator: Sendable {
    public typealias Completion = @Sendable (_ system: String, _ message: String) async throws -> String

    private let availability: @Sendable () -> AIAvailability
    private let complete: Completion
    private let budget: @Sendable () -> Int

    public init(
        availability: @escaping @Sendable () -> AIAvailability = { .current },
        complete: @escaping Completion = AIActionCoordinator.onDevice,
        budget: @escaping @Sendable () -> Int = {
            AIInputBudget.characters(contextTokens: AppleIntelligenceClient.contextTokens)
        }
    ) {
        self.availability = availability
        self.complete = complete
        self.budget = budget
    }

    /// Never throws: failures come back as `isError` results.
    /// `totalCharacters` is the length of the whole clip when `text` is only the start of it.
    public func run(action: AIAction, text: String, totalCharacters: Int? = nil) async -> AIResult {
        let preview = String(text.prefix(80)).replacingOccurrences(of: "\n", with: " ")
        let state = availability()
        guard state.isAvailable else {
            return AIResult(action: action, sourcePreview: preview, result: state.message, isError: true)
        }
        do {
            let input = AIInput.make(text, budget: budget(), totalCharacters: totalCharacters)
            let response = try await complete(action.systemPrompt, action.userMessage(for: input.text))
            return AIResult(action: action, sourcePreview: preview, result: response, coverage: input.coverage)
        } catch {
            return AIResult(action: action, sourcePreview: preview, result: describe(error), isError: true)
        }
    }

    // MARK: Long texts, a part at a time

    public enum PartOutcome: Sendable, Equatable {
        case answer(String)
        case failure(String)
    }

    /// The parts of a text for an action that reads in parts, or nil: a rewrite, the start of a bigger clip
    /// (`totalCharacters`, a masked or too-big clip), or a text that fits one request.
    public func parts(action: AIAction, text: String, totalCharacters: Int? = nil, fullLength: Int? = nil) -> AIParts? {
        guard action.readsInParts, totalCharacters == nil else { return nil }
        let size = budget()
        guard text.utf8.count > size else { return nil }
        let result = AIChunker.parts(of: text, budget: size, totalCharacters: fullLength)
        return result.parts.count > 1 ? result : nil
    }

    /// One model call for one part. Never throws: a failure comes back with its reason.
    public func summarizePart(action: AIAction, part: AIPart) async -> PartOutcome {
        await answer(action: action, text: part.text)
    }

    /// One more call over the part summaries (short), asked for by the person.
    public func combine(action: AIAction, answers: [String]) async -> PartOutcome {
        await answer(action: action, text: answers.joined(separator: "\n\n"))
    }

    private func answer(action: AIAction, text: String) async -> PartOutcome {
        let state = availability()
        guard state.isAvailable else { return .failure(state.message) }
        do {
            let input = AIInput.make(text, budget: budget())
            return try await .answer(complete(action.systemPrompt, action.userMessage(for: input.text)))
        } catch {
            return .failure(describe(error))
        }
    }

    /// The picture goes to Apple's local model and nowhere else.
    public func describeImage(_ imageData: Data) async -> AIResult {
        let state = availability()
        guard state.isAvailable else {
            return AIResult(action: .describeImage, sourcePreview: "Image", result: state.message, isError: true)
        }
        do {
            guard #available(macOS 27, *) else { throw AppleIntelligenceClient.ClientError.visionUnavailable }
            let description = try await AppleIntelligenceClient().describe(imageData: imageData)
            return AIResult(action: .describeImage, sourcePreview: "Image", result: description)
        } catch {
            return AIResult(
                action: .describeImage, sourcePreview: "Image", result: describe(error), isError: true
            )
        }
    }

    public static let onDevice: Completion = { system, message in
        guard #available(macOS 26, *) else { throw AppleIntelligenceClient.ClientError.unavailable }
        return try await AppleIntelligenceClient().complete(system: system, userMessage: message)
    }

    private func describe(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

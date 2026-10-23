// SPDX-License-Identifier: MIT
import Foundation

/// The set of AI transformations a user can apply to a clipboard item's text.
public enum AIAction: String, CaseIterable, Sendable {
    case summarize = "Summarize"
    case keyPoints = "Key Points"
    case toneProfessional = "Professional"
    case toneConcise = "Concise"
    case translate = "Translate"
    case extract = "Extract"
    /// On-device only: the image is never sent anywhere.
    case describeImage = "Describe Image"

    public static let textActions: [AIAction] = [
        .summarize,
        .keyPoints,
        .toneProfessional,
        .toneConcise,
        .translate,
        .extract
    ]

    /// A summary of what a text is about can be read a part at a time and each part's answer stands alone; a rewrite
    /// is as long as its input and cannot be stitched from parts (`docs/design/ai-chunked-summary.md`).
    public var readsInParts: Bool {
        self == .summarize || self == .keyPoints
    }

    public static func actions(for type: ClipboardType) -> [AIAction] {
        switch type {
        case .text, .code: textActions
        case .image: [.describeImage]
        case .url, .file, .color: []
        }
    }

    /// SF Symbol name for menus and result panels.
    public var symbolName: String {
        switch self {
        case .summarize: "text.quote"
        case .keyPoints: "checklist"
        case .toneProfessional: "briefcase"
        case .toneConcise: "arrow.down.right.and.arrow.up.left"
        case .translate: "globe"
        case .extract: "list.bullet.rectangle"
        case .describeImage: "photo.badge.magnifyingglass"
        }
    }

    /// System prompt sent to the on-device model on every request for this action.
    public var systemPrompt: String {
        switch self {
        case .summarize:
            "You are a precise summarizer. Respond with a 2-3 sentence summary only. No preamble, no labels."
        case .keyPoints:
            """
            Extract 3-5 main key points from the text as a concise bulleted list. \
            Respond with only the bullet points, no preamble.
            """
        case .toneProfessional:
            """
            Rewrite the text in a clear, professional, well-structured tone. Keep the core meaning. \
            Respond with only the rewritten text, no preamble or explanation.
            """
        case .toneConcise:
            """
            Rewrite the text to be as concise, direct, and high-signal as possible, \
            cutting unnecessary words. Respond with only the rewritten text, \
            no preamble or explanation.
            """
        case .translate:
            """
            You are a translator. Detect the source language.
            If the text is not in English, translate it to English.
            If it is already in English, translate it to Spanish.
            Respond with only the translation — no explanation, no language labels.
            """
        case .extract:
            """
            Extract key information from the text.
            Format as a concise bulleted list.
            Include: names, dates, emails, phone numbers, URLs, amounts, and important specifics.
            No preamble. If nothing notable is found, respond with "Nothing notable found."
            """
        case .describeImage:
            """
            Describe the image in two or three factual sentences. If it contains readable text, quote the main text. \
            No preamble.
            """
        }
    }

    /// Builds the user-turn message content for the given text payload. The coordinator has already cut it to the
    /// model's budget and told the person (`AIInput`).
    public func userMessage(for text: String) -> String {
        text
    }
}

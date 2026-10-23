// SPDX-License-Identifier: MIT

/// What one part answered, and where that part sits in the clip.
public struct AIPartAnswer: Sendable, Equatable {
    public let index: Int
    public let start: Int
    public let end: Int
    public let text: String
}

/// The part the panel offers next.
public struct AIPartNext: Sendable, Equatable {
    public let index: Int
    public let start: Int
    public let end: Int
}

/// A long text being summarized a part at a time: the parts, and what each answered so far. Held in memory only while
/// the
/// answer panel is open (`AppState.aiRun`); each part is one model call, made when the person asks for it.
public struct AIRun: Sendable {
    public let action: AIAction
    public let parts: AIParts
    public private(set) var answers: [String] = []
    /// The summary of the part summaries, once the person asked for one.
    public var combined: String?

    public init(action: AIAction, parts: AIParts) {
        self.action = action
        self.parts = parts
    }

    public var nextIndex: Int {
        answers.count
    }

    public var next: AIPart? {
        parts.parts.indices.contains(nextIndex) ? parts.parts[nextIndex] : nil
    }

    /// What a combine call reads: the part summaries, not the source text.
    public var answersForCombining: [String] {
        answers
    }

    public var isComplete: Bool {
        next == nil
    }

    /// What Paste and Copy give: the combined summary, or the answers so far, one after another.
    public var text: String {
        combined ?? answers.joined(separator: "\n\n")
    }

    public mutating func record(_ answer: String) {
        answers.append(answer)
    }

    public func progress(isReading: Bool, isCombining: Bool, failure: String?) -> AIResult.Progress {
        AIResult.Progress(
            answers: answers.enumerated().map { index, text in
                AIPartAnswer(
                    index: index + 1, start: parts.parts[index].start, end: parts.parts[index].end, text: text
                )
            },
            partCount: parts.parts.count,
            totalCharacters: parts.total,
            readableCharacters: parts.readable,
            next: next.map { AIPartNext(index: nextIndex + 1, start: $0.start, end: $0.end) },
            isReading: isReading,
            isCombining: isCombining,
            failure: failure,
            hasCombined: combined != nil
        )
    }
}

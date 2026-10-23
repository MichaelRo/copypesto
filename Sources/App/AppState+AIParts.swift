// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

extension AppState {
    /// The first part of a long summary is read at once, as a short text is; the rest wait for the person
    /// (`docs/design/ai-chunked-summary.md`). A failure of the first part is shown as any failure is.
    func startPartsRun(action: AIAction, text: String, parts: AIParts, isProtected: Bool, sourceItemID: UUID?) async {
        var run = AIRun(action: action, parts: parts)
        let preview = String(text.prefix(80)).replacingOccurrences(of: "\n", with: " ")
        guard let first = run.next else { return aiIsLoading = false }
        switch await aiCoordinator.summarizePart(action: action, part: first) {
        case let .answer(answer):
            run.record(answer)
            aiRun = run
            publish(AIResult(
                action: action, sourcePreview: preview, result: run.text, isProtected: isProtected,
                sourceItemID: sourceItemID, progress: run.progress(isReading: false, isCombining: false, failure: nil)
            ))
        case let .failure(message):
            aiResult = AIResult(action: action, sourcePreview: preview, result: message, isError: true)
        }
        aiIsLoading = false
    }

    /// One model call for the next part, when the person asks for it. Cancel keeps the parts already read.
    func readNextAIPart() {
        guard let run = aiRun, let part = run.next, let current = aiResult, aiPartTask == nil else { return }
        publish(current.with(
            result: run.text, progress: run.progress(isReading: true, isCombining: false, failure: nil)
        ))
        aiPartTask = Task { [aiCoordinator] in
            let outcome = await aiCoordinator.summarizePart(action: run.action, part: part)
            finishPart(outcome)
        }
    }

    func combineAIParts() {
        guard let run = aiRun, run.isComplete, run.combined == nil, let current = aiResult, aiPartTask == nil else {
            return
        }
        publish(current.with(
            result: run.text, progress: run.progress(isReading: false, isCombining: true, failure: nil)
        ))
        aiPartTask = Task { [aiCoordinator] in
            let outcome = await aiCoordinator.combine(action: run.action, answers: run.answersForCombining)
            guard !Task.isCancelled, var latest = aiRun, let latestResult = aiResult else { return }
            aiPartTask = nil
            switch outcome {
            case let .answer(summary):
                latest.combined = summary
                aiRun = latest
                publish(latestResult.with(
                    result: latest.text, progress: latest.progress(isReading: false, isCombining: false, failure: nil)
                ))
            case let .failure(message):
                publish(latestResult.with(
                    result: latest.text, progress: latest.progress(
                        isReading: false,
                        isCombining: false,
                        failure: message
                    )
                ))
            }
        }
    }

    func cancelAIPart() {
        aiPartTask?.cancel()
        aiPartTask = nil
        guard let run = aiRun, let current = aiResult else { return }
        publish(current.with(
            result: run.text, progress: run.progress(isReading: false, isCombining: false, failure: nil)
        ))
    }

    private func finishPart(_ outcome: AIActionCoordinator.PartOutcome) {
        guard !Task.isCancelled, var run = aiRun, let current = aiResult else { return }
        aiPartTask = nil
        switch outcome {
        case let .answer(answer):
            run.record(answer)
            aiRun = run
            publish(current.with(
                result: run.text, progress: run.progress(isReading: false, isCombining: false, failure: nil)
            ))
        case let .failure(message):
            publish(current.with(
                result: run.text, progress: run.progress(isReading: false, isCombining: false, failure: message)
            ))
        }
    }

    private func publish(_ result: AIResult) {
        aiResult = result
        AIResultAnnouncement.announce(result)
    }
}

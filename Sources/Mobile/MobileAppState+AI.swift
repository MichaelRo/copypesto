// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore
import SwiftData
import UIKit

/// AI actions and Describe Image on iOS (ADR 0058): Apple's on-device model only, through Core's coordinator, the
/// same switch and the same rules as the Mac (ADR 0005). Nothing a clip holds goes to a service; a secret is never
/// offered; the answer lives in `aiResult` while its sheet is up and is gone with the lock.
extension MobileAppState {
    private static let aiLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileAI")

    static func makeAICoordinator() -> AIActionCoordinator {
        guard RuntimeConfiguration.current.mode == .uiTest, RuntimeConfiguration.current.aiFixture else {
            return AIActionCoordinator()
        }
        return AIActionCoordinator(
            availability: { .available },
            complete: { _, message in "Summary: " + message.prefix(24) },
            budget: { 300 }
        )
    }

    static func makeAIAvailability() -> @Sendable () -> AIAvailability {
        { AIAvailability.current }
    }

    func aiFacts(for item: ClipboardItem) -> CardAIActions.Facts {
        CardAIActions.Facts(
            type: item.type, isSecret: item.sensitivityRaw != nil,
            isCovered: secretReveal.concealment(for: item).isConcealed, isFiltered: item.isNSFW,
            isPending: item.analysisPending, isLocked: isHistoryLocked, availability: aiAvailability(),
            supportsVision: aiSupportsVision()
        )
    }

    func aiOffer(for item: ClipboardItem) -> CardAIActions.Offer {
        CardAIActions.offer(for: aiFacts(for: item))
    }

    /// Runs one action on the clip and presents the sheet. A second request replaces the first.
    func runAIAction(_ action: AIAction, on item: ClipboardItem) {
        guard !isHistoryLockedNow() else { return }
        let offer = aiOffer(for: item)
        guard offer.isEnabled, offer.actions.contains(action) else { return }
        aiTask?.cancel()
        aiResult = nil
        aiIsLoading = true
        showsAI = true
        let coordinator = aiCoordinator
        if action == .describeImage {
            let (container, id) = (historyContainer, item.id)
            aiTask = Task { [weak self] in
                let result = await Self.describe(itemID: id, container: container, coordinator: coordinator)
                self?.finishAI(result)
            }
            return
        }
        let source = aiSource(for: item)
        aiTask = Task { [weak self] in
            let result = await coordinator.run(
                action: action,
                text: source.text,
                totalCharacters: source.totalCharacters
            )
            self?.finishAI(result)
        }
    }

    /// The whole text of an ordinary clip, so a long document is summarized and not its first 500 characters; a clip
    /// too big to decrypt on the main actor falls back to its preview, which the answer then says.
    private func aiSource(for item: ClipboardItem) -> (text: String, totalCharacters: Int?) {
        guard DetailPopoverContent.canRead(byteSize: item.byteSize) else {
            return (item.gridPreview, item.textLength > 0 ? item.textLength : nil)
        }
        return (item.blob?.decryptedText() ?? item.displayPreviewText, nil)
    }

    private static func describe(
        itemID: UUID, container: ModelContainer?, coordinator: AIActionCoordinator
    ) async
    -> AIResult {
        guard let container else {
            return AIResult(action: .describeImage, sourcePreview: "Image", result: unreadablePicture, isError: true)
        }
        let service = await ThumbnailServices.shared.service(for: container)
        guard let thumbnail = await service.thumbnail(for: itemID, maxPixel: 1024) else {
            return AIResult(action: .describeImage, sourcePreview: "Image", result: unreadablePicture, isError: true)
        }
        return await coordinator.describeImage(thumbnail.data)
    }

    private static var unreadablePicture: String {
        String(localized: "That picture couldn\u{2019}t be read.")
    }

    private func finishAI(_ result: AIResult) {
        guard !Task.isCancelled, showsAI else { return }
        aiResult = result
        aiIsLoading = false
        aiTask = nil
        if result.isError {
            Self.aiLogger.error("An AI action failed: \(result.action.rawValue, privacy: .public)")
        }
        UIAccessibility.post(notification: .announcement, argument: Self.announcement(for: result))
    }

    static func announcement(for result: AIResult) -> String {
        let name = String(localized: result.action.title)
        if result.isError { return String(localized: "\(name) failed. \(result.result)") }
        let note = result.coverage.flatMap { $0.isPartial ? " " + $0.note : nil } ?? ""
        return String(localized: "\(name) result: \(result.result)") + note
    }

    /// Done, or the history locking: the answer, and anything still being worked out for it, goes.
    func closeAI() {
        aiTask?.cancel()
        aiTask = nil
        aiResult = nil
        aiIsLoading = false
        showsAI = false
    }

    /// Copy in the sheet: the answer goes on the clipboard and becomes a clip of its own, as Copy Recognized Text
    /// does (ADR 0037), because iOS has no watcher to capture it.
    @discardableResult
    func copyAIResult() async -> Bool {
        guard let result = aiResult, result.canPaste else { return false }
        MobileClipboard.write(.text(result.result), protected: false)
        await add(ClipCapture.text(result.result))
        tell(String(localized: "Copied"))
        return true
    }
}

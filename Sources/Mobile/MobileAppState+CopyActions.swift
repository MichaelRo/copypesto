// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore
import Photos

/// What the Copy As, Copy Recognized Text and Save to Photos entries of a clip's menu do. Every clipboard write goes
/// through `MobileClipboard`; a clip a lock or a cover hides is never read.
extension MobileAppState {
    private static let copyActionsLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileCopyActions")

    func copyActionFacts(for item: ClipboardItem) -> CardCopyActions.Facts {
        let concealment = secretReveal.concealment(for: item)
        let isLocked = isHistoryLockedNow()
        return CardCopyActions.Facts(
            type: item.type, isSecret: item.sensitivityRaw != nil, isCovered: concealment.isConcealed,
            isFiltered: item.isNSFW, isPending: item.analysisPending,
            hasColor: item.type == .color && ColorLiteralParser.firstColor(in: item.displayPreviewText) != nil,
            offersRecognizedText: item.type == .image && !isLocked && RecognizedText.isOffered(for: item),
            isJWT: item.sensitivity == .jwt && !isLocked, allowsDecode: concealment.allowsDecode,
            canAuthenticate: secretReveal.canAuthenticate,
            structured: isLocked ? [] : StructuredPaste.offered(for: item)
        )
    }

    func copyOffer(for item: ClipboardItem) -> CardCopyActions.Offer {
        CardCopyActions.offer(for: copyActionFacts(for: item))
    }

    @discardableResult
    func copyTransformed(_ item: ClipboardItem, by transform: TextTransform) -> Bool {
        let offer = copyOffer(for: item)
        if offer.structured.contains(transform) {
            guard let text = StructuredPaste.result(of: transform, for: item) else { return false }
            return finishCopy(item, content: .text(text))
        }
        guard offer.transforms.contains(transform),
              let text = ClipContent.of(item)?.plainText else { return false }
        return finishCopy(item, content: .text(transform.apply(to: text, language: item.detectedLanguage)))
    }

    /// Decode JWT (ADR 0020): the same authentication as Show, the token read and held for the sheet in memory only.
    /// Nil when it was not offered, was refused, or the clip is not a readable token.
    @discardableResult
    func decodeJWT(_ item: ClipboardItem) async -> JWTDecodeResult? {
        guard copyOffer(for: item).offersDecodeJWT else { return nil }
        guard await secretReveal.authenticate(reason: String(localized: "Decode the hidden token")) else { return nil }
        let result: JWTDecodeResult = JWTDecoder.decode(item.blob?.decryptedText() ?? item.displayPreviewText)
            .map(JWTDecodeResult.decoded)
            ?? .unreadable
        decodedJWT = result
        return result
    }

    /// Copy Payload: the payload goes out as a secret does (this device only, gone after a while).
    func copyDecodedPayload(_ decoding: JWTDecoding) {
        MobileClipboard.write(.text(decoding.payloadJSON), protected: true)
        decodedJWT = nil
        tell(String(localized: "Copied"))
    }

    @discardableResult
    func copyColor(_ item: ClipboardItem, as format: ColorCopyFormat) -> Bool {
        guard copyOffer(for: item).colorFormats.contains(format),
              let color = ColorLiteralParser.firstColor(in: item.displayPreviewText) else { return false }
        return finishCopy(item, content: .text(format.string(for: color)))
    }

    /// ADR 0037: the recognized text goes on the clipboard and becomes a clip of its own; the picture stays.
    @discardableResult
    func copyRecognizedText(of item: ClipboardItem, store: RecognizedTextStore = RecognizedTextStore()) async -> Bool {
        guard copyOffer(for: item).offersRecognizedText, let text = RecognizedText.text(of: item, store: store) else {
            tell(String(localized: "Couldn\u{2019}t read the text in this picture."), isProblem: true)
            return false
        }
        MobileClipboard.write(.text(text), protected: false)
        await add(ClipCapture.text(text))
        tell(String(localized: "Copied"))
        return true
    }

    func saveToPhotos(_ item: ClipboardItem) async {
        guard copyOffer(for: item).offersSaveToPhotos, let data = item.blob?.decryptedData() else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            tell(String(localized: "Saved to Photos"))
        } catch {
            Self.copyActionsLogger.error("Save to Photos failed: \(error.localizedDescription, privacy: .public)")
            tell(String(localized: "Couldn\u{2019}t save to Photos."), isProblem: true)
        }
    }
}

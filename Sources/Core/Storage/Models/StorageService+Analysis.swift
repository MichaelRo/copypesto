// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

/// What judging a copy needs, held apart from the clip so the judging can happen after the clip is saved.
struct IngestAnalysisInput {
    let clipType: ClipboardType
    /// The picture's bytes, for reading its text and asking the model about it.
    let image: Data?
    /// The text after the ingest rules (for a picture, empty), which is scanned for secrets.
    let text: String
    /// The address, for the link check.
    let link: String?
    /// Where the media/image came from (e.g. from an HTML <img> tag or source address).
    let sourceURL: URL?
    let readsImages: Bool
    let screensContent: Bool
    var needsPerceptualHash = false

    /// Text larger than this is scanned after it is saved: the scan took 430 ms for 5 MB.
    static let backgroundTextBytes = 100_000

    /// Pictures are read and shown to the model; both take hundreds of milliseconds, so the card appears first.
    var runsInTheBackground: Bool {
        switch clipType {
        case .image: readsImages || screensContent || needsPerceptualHash
        case .text, .code: text.utf8.count > Self.backgroundTextBytes
        default: false
        }
    }
}

/// What the judging found.
struct IngestAnalysis {
    /// The first `CardPreviewText.previewLength` characters of the picture's text: its preview.
    var ocrText: String?
    /// The whole text, up to `RecognizedText.maxBytes` (ADR 0034). Kept in a file only when it is longer than the
    /// preview and nothing in it is a secret.
    var recognizedText: String?
    var isNSFW = false
    var sensitivity: SensitiveContentDetector.Result?
    var perceptualHash: String?
}

extension StorageService {
    static let analysisSlots = 2
    static let analysisLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "IngestAnalysis")

    /// Reads a picture's text, asks the model about it, checks a link, and scans text for secrets. Pure of the store,
    /// so
    /// it runs off this actor while the clip is already on the shelf.
    nonisolated static func analyze(
        _ input: IngestAnalysisInput, recognizer: any TextRecognizing, screener: any ImageSensitivityScreening
    ) async
    -> IngestAnalysis {
        var analysis = IngestAnalysis()
        if input.clipType == .image, let image = input.image {
            if input.needsPerceptualHash {
                analysis.perceptualHash = PerceptualHasher.hash(imageData: image)
            }
            if input.readsImages {
                if let read = await recognizer.recognize(imageData: image) {
                    let whole = RecognizedText.capped(read)
                    analysis.recognizedText = whole
                    analysis.ocrText = String(whole.prefix(CardPreviewText.previewLength))
                }
            }
            if input.screensContent {
                if let source = input.sourceURL, NSFWURLDetector.isExplicit(urlString: source.absoluteString) {
                    analysis.isNSFW = true
                } else if let ocr = analysis.recognizedText, NSFWURLDetector.keywordScore(in: ocr) >= 0.85 {
                    analysis.isNSFW = true
                } else {
                    analysis.isNSFW = await screener.isSensitive(imageData: image)
                }
            }
        } else if input.clipType == .url, input.screensContent, let link = input.link {
            analysis.isNSFW = NSFWURLDetector.isExplicit(urlString: link)
        }
        let text = input.text
        // Text found inside a picture is content too: a screenshot of a terminal can hold an API key.
        analysis.sensitivity = if text.utf8.count > IngestAnalysisInput.backgroundTextBytes {
            await Task.detached(priority: .utility) { SensitiveContentDetector.detect(in: text) }.value
        } else {
            SensitiveContentDetector.detect(in: text)
        }
        // The whole text is scanned, not the preview: what is kept for Copy Recognized Text must hold no secret.
        if analysis.sensitivity == nil, let ocr = analysis.recognizedText {
            analysis.sensitivity = SensitiveContentDetector.detectAnywhere(in: ocr)
        }
        return analysis
    }

    /// A UI-test launch skips text recognition (it is slow and judges nothing), except for the film's seed, whose
    /// boarding pass must be findable by the words inside it.
    nonisolated static func readsImages(in configuration: RuntimeConfiguration) -> Bool {
        configuration.mode != .uiTest || configuration.seed == .lunchRush
    }

    func input(
        for clipType: ClipboardType, image: Data?, text: String, link: String?, sourceURL: URL? = nil,
        needsPerceptualHash: Bool = false
    )
    -> IngestAnalysisInput {
        IngestAnalysisInput(
            clipType: clipType, image: image, text: text, link: link, sourceURL: sourceURL,
            readsImages: Self.readsImages(in: RuntimeConfiguration.current),
            screensContent: nsfwModeProvider().detectsContent,
            needsPerceptualHash: needsPerceptualHash
        )
    }

    /// Judges a clip that was saved without being judged, then fills in what was found. Tracked, so
    /// `waitForBackgroundWork()` and a test can wait for it.
    func startAnalysis(of itemID: UUID, input: IngestAnalysisInput) {
        let recognizer = textRecognizer
        let screener = imageScreener
        let taskID = UUID()
        if input.clipType == .image, let imageData = input.image {
            Task.detached(priority: .userInitiated) {
                ThumbnailService.prewarm(id: itemID, imageData: imageData, maxPixel: 480)
            }
        }
        pendingAnalyses[taskID] = Task.detached(priority: .utility) { [self] in
            await acquireAnalysisSlot()
            let judging = PerfSignposts.copy.begin("analysis")
            let analysis = await Self.analyze(input, recognizer: recognizer, screener: screener)
            await finishAnalysis(of: itemID, input: input, analysis: analysis)
            judging.end()
            await releaseAnalysisSlot()
            await endAnalysis(taskID)
        }
    }

    /// Two clips are judged at a time: restoring a backup of a thousand pictures must not start a thousand readings
    /// and a thousand model sessions at once.
    private func acquireAnalysisSlot() async {
        if runningAnalyses < Self.analysisSlots {
            runningAnalyses += 1
            return
        }
        await withCheckedContinuation { analysisQueue.append($0) }
    }

    private func releaseAnalysisSlot() {
        if analysisQueue.isEmpty {
            runningAnalyses -= 1
        } else {
            analysisQueue.removeFirst().resume()
        }
    }

    func endAnalysis(_ id: UUID) {
        pendingAnalyses[id] = nil
    }

    /// Stores the verdict on the clip and uncovers it. A clip deleted meanwhile stays deleted.
    func finishAnalysis(of itemID: UUID, input: IngestAnalysisInput, analysis: IngestAnalysis) {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == itemID })
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first, item.analysisPending else { return }
        // A copy a password manager marked concealed already carries its own hidden preview; the scan adds nothing to
        // it.
        if item.sensitivityRaw == nil {
            let sensitivity = analysis.sensitivity
            let preview = sensitivity?.maskedPreview ?? analysis.ocrText ?? String(input.text.prefix(500))
            do {
                let sealed = try storedPreview(
                    for: item.id, clipType: input.clipType, sensitivity: sensitivity, preview: preview
                )
                item.previewText = sealed.plain
                item.previewCiphertext = sealed.envelope?.ciphertext
                item.previewNonce = sealed.envelope?.nonce
                item.previewAADBound = sealed.envelope != nil
            } catch {
                // A preview that cannot be sealed is not stored in the clear: the clip keeps no preview (ADR 0002).
                Self.analysisLogger
                    .error("Preview not sealed after analysis: \(error.localizedDescription, privacy: .public)")
            }
            if let sensitivity {
                item.sensitivityRaw = sensitivity.category.rawValue
                item.sensitivityMaskedPreview = sensitivity.maskedPreview
            }
        }
        if item.perceptualHash == nil, let computedHash = analysis.perceptualHash {
            item.perceptualHash = computedHash
        }
        item.isNSFW = analysis.isNSFW
        item.analysisPending = false
        do {
            try saveOrRollback()
        } catch {
            Self.analysisLogger.error("Analysis not saved: \(error.localizedDescription, privacy: .public)")
            return
        }
        keepRecognizedText(analysis.recognizedText, for: item)
        mirrorToLastItemFile(item)
        startEmbedding(for: item, text: input.text)
    }

    /// The whole text of a picture is kept in its own sealed file when the preview cut it (ADR 0034), after the clip is
    /// saved, so a failed save leaves no file. A secret keeps none: only the mask is stored for it.
    private func keepRecognizedText(_ text: String?, for item: ClipboardItem) {
        guard item.type == .image, item.sensitivityRaw == nil, let text, RecognizedText.needsFile(text) else { return }
        do {
            try recognizedTexts.save(text, for: item.id)
        } catch {
            Self.analysisLogger
                .error("Recognized text not kept: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clips left pending by an app that quit mid-judging are judged again, from their stored data.
    public func resumePendingAnalysis() async {
        let descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.analysisPending })
        guard let pending = try? modelContext.fetch(descriptor) else { return }
        for item in pending {
            guard let data = item.blob?.decryptedData() else {
                item.analysisPending = false
                continue
            }
            let isImage = item.type == .image
            let text = isImage ? "" : String(bytes: data, encoding: .utf8) ?? ""
            startAnalysis(
                of: item.id,
                input: input(for: item.type, image: isImage ? data : nil, text: text, link: nil)
            )
        }
        try? saveOrRollback()
    }
}

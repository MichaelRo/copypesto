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
    let readsImages: Bool
    let screensContent: Bool

    /// Text larger than this is scanned after it is saved: the scan took 430 ms for 5 MB.
    static let backgroundTextBytes = 100_000

    /// Pictures are read and shown to the model; both take hundreds of milliseconds, so the card appears first.
    var runsInTheBackground: Bool {
        switch clipType {
        case .image: readsImages || screensContent
        case .text, .code: text.utf8.count > Self.backgroundTextBytes
        default: false
        }
    }
}

/// What the judging found.
struct IngestAnalysis {
    var ocrText: String?
    var isNSFW = false
    var sensitivity: SensitiveContentDetector.Result?
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
            if input.readsImages {
                analysis.ocrText = await recognizer.recognize(imageData: image).map { String($0.prefix(500)) }
            }
            if input.screensContent { analysis.isNSFW = await screener.isSensitive(imageData: image) }
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
        if analysis.sensitivity == nil, let ocr = analysis.ocrText {
            analysis.sensitivity = SensitiveContentDetector.detectAnywhere(in: ocr)
        }
        return analysis
    }

    func input(for clipType: ClipboardType, image: Data?, text: String, link: String?) -> IngestAnalysisInput {
        IngestAnalysisInput(
            clipType: clipType, image: image, text: text, link: link,
            readsImages: RuntimeConfiguration.current.mode != .uiTest,
            screensContent: nsfwModeProvider().detectsContent
        )
    }

    /// Judges a clip that was saved without being judged, then fills in what was found. Tracked, so
    /// `waitForBackgroundWork()` and a test can wait for it.
    func startAnalysis(of itemID: UUID, input: IngestAnalysisInput) {
        let recognizer = textRecognizer
        let screener = imageScreener
        let taskID = UUID()
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
        if item.perceptualHash == nil, input.clipType == .image, let data = input.image {
            item.perceptualHash = PerceptualHasher.hash(imageData: data)
        }
        item.isNSFW = analysis.isNSFW
        item.analysisPending = false
        do {
            try saveOrRollback()
        } catch {
            Self.analysisLogger.error("Analysis not saved: \(error.localizedDescription, privacy: .public)")
            return
        }
        mirrorToLastItemFile(item)
        startEmbedding(for: item, text: input.text)
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

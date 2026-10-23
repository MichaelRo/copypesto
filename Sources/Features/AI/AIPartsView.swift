// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The parts of a long summary read so far, each under the characters it covers (`docs/design/ai-chunked-summary.md`).
struct AIPartsList: View {
    let progress: AIResult.Progress
    let combined: String?

    private func label(_ answer: AIPartAnswer) -> String {
        let range = "\(answer.start.formatted())–\(answer.end.formatted())"
        return String(localized: "Part \(answer.index) of \(progress.partCount) · characters \(range)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(progress.answers, id: \.index) { answer in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label(answer)).pestoCaption()
                    Text(answer.text)
                        .scaledFont(size: 12.5)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
            if let combined {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Combined summary").pestoCaption()
                    Text(combined)
                        .scaledFont(size: 12.5, weight: .medium)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// What the panel asks under the parts: read the next one, wait for it, retry a failure, combine, or say what was left
/// out.
struct AIPartsControls: View {
    let progress: AIResult.Progress
    let onReadNext: () -> Void
    let onCancel: () -> Void
    let onCombine: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.horizontal, 16)
            row.padding(.horizontal, 16)
            if progress.isCut, progress.next == nil {
                Text(AIResultTitle.coverageNote(.init(
                    shown: progress.readableCharacters,
                    total: progress.totalCharacters
                )))
                .pestoCaption()
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var row: some View {
        if progress.isReading || progress.isCombining {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress.isCombining
                    ? String(localized: "Combining the parts\u{2026}")
                    : String(localized: "Reading part \(progress.answers.count + 1) of \(progress.partCount)\u{2026}"))
                    .pestoCaption()
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier(AccessibilityID.aiCancelPartButton)
            }
        } else if let failure = progress.failure {
            HStack(spacing: 8) {
                Text(failure).font(.caption).foregroundStyle(Color.statusBad).lineLimit(2)
                Spacer()
                Button("Try Again", action: progress.next == nil ? onCombine : onReadNext)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier(AccessibilityID.aiTryAgainButton)
            }
        } else if let next = progress.next {
            HStack(spacing: 8) {
                Text("Read the next part?").pestoCaption()
                Spacer()
                Button(String(localized: "Read Part \(next.index)"), action: onReadNext)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "Read part \(next.index) of \(progress.partCount)"))
                    .accessibilityIdentifier(AccessibilityID.aiReadNextPartButton)
            }
        } else if !progress.hasCombined {
            HStack(spacing: 8) {
                Text("All \(progress.partCount) parts read.").pestoCaption()
                Spacer()
                Button("Combine Into One Summary", action: onCombine)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier(AccessibilityID.aiCombineButton)
            }
        }
    }
}

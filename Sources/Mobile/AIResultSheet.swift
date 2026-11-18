// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The answer of an AI action: what the model said, when it read only the start of a long clip, and Copy. Done, a
/// drag down and the history locking all drop it.
struct AIResultSheet: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.pestoSurface) private var ground

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if appState.aiIsLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Working\u{2026}").foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(MobileAccessibilityID.aiWorking)
                    } else if let result = appState.aiResult {
                        answer(result)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { appState.closeAI() }
                        .accessibilityIdentifier(MobileAccessibilityID.aiDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { Task { await appState.copyAIResult() } }
                        .disabled(appState.aiResult?.canPaste != true)
                        .accessibilityIdentifier(MobileAccessibilityID.aiCopy)
                }
            }
        }
        .accessibilityIdentifier(MobileAccessibilityID.aiSheet)
    }

    private var title: String {
        guard let result = appState.aiResult else { return String(localized: "AI Actions") }
        return result.isError ? String(localized: "\(result.action.rawValue) failed") : result.action.rawValue
    }

    @ViewBuilder
    private func answer(_ result: AIResult) -> some View {
        Text(result.result)
            .font(.body)
            .foregroundStyle(result.isError ? .secondary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(MobileAccessibilityID.aiAnswer)
        if let coverage = result.coverage, coverage.isPartial {
            Text(coverage.note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Text("Made on this device. Nothing you copied was sent anywhere.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

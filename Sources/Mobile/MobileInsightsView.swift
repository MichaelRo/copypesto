// SPDX-License-Identifier: MIT
import Charts
import PestoCore
import SwiftUI

struct MobileInsightsView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.pestoAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @State private var summary = InsightsSummary()
    @State private var range: InsightsDateRange = .sevenDays

    private var isPrivate: Bool {
        appState.isHistoryLocked || scenePhase != .active
    }

    var body: some View {
        Form {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(InsightsDateRange.allCases, id: \.self) { Text($0.label) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(isPrivate)
            } header: {
                Text("Activity")
            }

            if isPrivate {
                Section {
                    ContentUnavailableView(
                        appState.isHistoryLocked ? "History is locked" : "Hidden while away",
                        systemImage: "lock",
                        description: Text(
                            appState.isHistoryLocked
                                ? "Unlock your history to view activity insights."
                                : "Return to Pesto to view activity insights."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else if !summary.hasItems {
                Section {
                    ContentUnavailableView(
                        "No clipboard history yet",
                        systemImage: "clipboard",
                        description: Text("Copy some clips and come back.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                dailySection
                typeSection
                if !summary.topSources.isEmpty { topSourcesSection }
                topPastedSection
            }
        }
        .tint(accent)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(MobileAccessibilityID.insightsView)
        .task(id: TaskKey(range: range, locked: appState.isHistoryLocked, active: scenePhase == .active)) {
            if isPrivate {
                summary = InsightsSummary()
            } else {
                await loadSummary()
            }
        }
    }

    private struct TaskKey: Hashable {
        let range: InsightsDateRange
        let locked: Bool
        let active: Bool
    }

    private var dailySection: some View {
        Section("Copies per day") {
            Chart(summary.dailyCounts) { entry in
                BarMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Copies", entry.count)
                )
                .foregroundStyle(accent.gradient)
                .clipShape(.rect(cornerRadius: 3))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .sevenDays ? 1 : 5)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 120)
            .padding(.vertical, 4)
        }
    }

    private var typeSection: some View {
        Section("Type distribution") {
            HStack(alignment: .center, spacing: 16) {
                Chart(summary.typeCounts) { entry in
                    SectorMark(
                        angle: .value("Count", entry.count),
                        innerRadius: .ratio(0.52),
                        angularInset: 1.5
                    )
                    .clipShape(.rect(cornerRadius: 4))
                    .foregroundStyle(by: .value("Type", entry.label))
                }
                .frame(width: 112, height: 112)
                .chartLegend(.hidden)
                .chartForegroundStyleScale(
                    domain: summary.typeCounts.map(\.label),
                    range: summary.typeCounts.map { typeColor($0.kind) }
                )

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.typeCounts) { entry in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(typeColor(entry.kind))
                                .frame(width: 8, height: 8)
                            Text(entry.label)
                                .font(.caption)
                            Spacer()
                            Text("\(entry.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var topSourcesSection: some View {
        Section("Top sources") {
            ForEach(summary.topSources) { source in
                HStack(spacing: 10) {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(source.name)
                        .font(.callout)
                    Spacer()
                    Text("\(source.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var topPastedSection: some View {
        Section("Most pasted") {
            if appState.secretReveal.isContentCovered {
                Text("Hidden while screen sharing or recording is on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if summary.topPasted.isEmpty {
                Text("No clips pasted yet in this period.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.topPasted) { entry in
                    HStack(spacing: 10) {
                        Text(entry.preview)
                            .font(.callout)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer()
                        Text("\u{2191} \(entry.count)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(entry.count) pastes")
                    }
                }
            }
        }
    }

    private func loadSummary() async {
        guard !appState.isHistoryLockedNow(),
              scenePhase == .active,
              let container = appState.historyContainer else
        {
            summary = InsightsSummary()
            return
        }
        let result = await InsightsBuilder.build(
            in: container,
            range: range,
            unknownSourceLabel: String(localized: "Unknown")
        )
        guard !Task.isCancelled, !appState.isHistoryLockedNow(), scenePhase == .active else {
            summary = InsightsSummary()
            return
        }
        summary = result
    }

    private func typeColor(_ kind: ClipboardType) -> Color {
        switch kind {
        case .text: .blue
        case .image: .green
        case .url: .orange
        case .file: .brown
        case .color: .purple
        case .code: .teal
        }
    }
}

// SPDX-License-Identifier: MIT
import Charts
import PestoCore
import SwiftUI

struct InsightsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.pestoAccent) private var accent
    @AppStorage(Setting.screenSharingPrivacy) private var screenSharingPrivacy
    @State private var summary = InsightsSummary()
    @State private var range: InsightsDateRange = .sevenDays

    var body: some View {
        Group {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(InsightsDateRange.allCases, id: \.self) { Text($0.label) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Activity")
            }

            if !summary.hasItems {
                Section {
                    ContentUnavailableView(
                        "No clipboard history yet",
                        systemImage: "clipboard",
                        description: Text("Copy some clips and come back.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                dailySection
                typeSection
                topSourcesSection
                if !appState.isContentCovered(screenSharingPrivacy: screenSharingPrivacy) {
                    topPastedSection
                }
            }
        }
        .task(id: range) { await loadSummary() }
    }

    // MARK: - Chart sections

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
            .frame(height: 100)
            .padding(.vertical, 4)
        }
    }

    private var typeSection: some View {
        Section("Type distribution") {
            HStack(alignment: .top, spacing: 16) {
                Chart(summary.typeCounts) { entry in
                    SectorMark(
                        angle: .value("Count", entry.count),
                        innerRadius: .ratio(0.52),
                        angularInset: 1.5
                    )
                    .clipShape(.rect(cornerRadius: 4))
                    .foregroundStyle(by: .value("Type", entry.label))
                }
                .frame(width: 120, height: 120)
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
                                .pestoQuiet()
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    private var topPastedSection: some View {
        Section("Most pasted") {
            if summary.topPasted.isEmpty {
                Text("No clips pasted yet in this period.")
                    .pestoCaption()
            } else {
                ForEach(summary.topPasted) { entry in
                    HStack(spacing: 10) {
                        Text(entry.preview)
                            .font(.callout)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer()
                        Text("↑ \(entry.count)")
                            .font(.callout.monospacedDigit())
                            .pestoQuiet()
                            .accessibilityLabel("\(entry.count) pastes")
                    }
                }
            }
        }
    }

    private var topSourcesSection: some View {
        Section("Top sources") {
            ForEach(summary.topSources) { source in
                HStack(spacing: 10) {
                    if let img = SourceIconCache.shared.image(forBundleID: source.bundleID) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "app.dashed")
                            .frame(width: 22, height: 22)
                            .pestoQuiet()
                            .accessibilityHidden(true)
                    }
                    Text(source.name)
                        .font(.callout)
                    Spacer()
                    Text("\(source.count)")
                        .font(.callout.monospacedDigit())
                        .pestoQuiet()
                }
            }
        }
    }

    // MARK: - Data loading

    private func loadSummary() async {
        guard !appState.isHistoryLockedNow(), let container = appState.historyContainer else {
            summary = InsightsSummary()
            return
        }
        let result = await InsightsBuilder.build(
            in: container,
            range: range,
            unknownSourceLabel: String(localized: "Unknown")
        )
        guard !Task.isCancelled, !appState.isHistoryLockedNow() else {
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

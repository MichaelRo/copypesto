// SPDX-License-Identifier: MIT
import Charts
import PestoCore
import SwiftData
import SwiftUI

struct SourceSummary: Identifiable {
    let id: String // bundleID
    var bundleID: String? {
        id == "unknown" ? nil : id
    }

    let name: String
    let count: Int
}

/// Pre-aggregated snapshot stored in @State — avoids retaining thousands of ClipboardItem
/// model objects on the main actor after the fetch completes.
private struct InsightsSummary {
    var dailyCounts: [(date: Date, count: Int)] = []
    var typeCounts: [(label: String, count: Int)] = []
    var topSources: [SourceSummary] = []
    var topPasted: [(preview: String, count: Int)] = []
    var hasItems: Bool {
        !dailyCounts.isEmpty || !typeCounts.isEmpty
    }
}

struct InsightsView: View {
    @Environment(\.pestoAccent) private var accent
    @Environment(\.modelContext) private var modelContext
    @State private var summary = InsightsSummary()
    @State private var range: DateRange = .week

    enum DateRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"

        var days: Int {
            self == .week ? 7 : 30
        }
    }

    var body: some View {
        Group {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(DateRange.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Activity").settingsRow("Activity insights")
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
                topPastedSection
            }
        }
        .task(id: range) { await loadSummary() }
    }

    // MARK: - Chart sections

    private var dailySection: some View {
        Section("Copies per day") {
            Chart(summary.dailyCounts, id: \.date) { entry in
                BarMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Copies", entry.count)
                )
                .foregroundStyle(accent.gradient)
                .clipShape(.rect(cornerRadius: 3))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) {
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
                Chart(summary.typeCounts, id: \.label) { entry in
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

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.typeCounts, id: \.label) { entry in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(typeColor(entry.label))
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
                ForEach(Array(summary.topPasted.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 10) {
                        Text(entry.preview)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text("↑ \(entry.count)")
                            .font(.callout.monospacedDigit())
                            .pestoQuiet()
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
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -range.days, to: .now) ?? .distantPast
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.timestamp > cutoff },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        // Cap at 5,000 — enough for ~166 copies/day over 30 days. Aggregate only; no objects retained after this
        // function.
        descriptor.fetchLimit = 5000
        guard let items = try? modelContext.fetch(descriptor) else { return }

        // Aggregate on the spot so we retain counts, not model objects.
        let daily = buildDailyCounts(items: items, cal: cal, cutoff: cutoff)
        let types = buildTypeCounts(items: items)
        let sources = buildTopSources(items: items)
        let pasted = buildTopPasted(items: items)

        summary = InsightsSummary(
            dailyCounts: daily,
            typeCounts: types,
            topSources: sources,
            topPasted: pasted
        )
    }

    private func buildDailyCounts(
        items: [ClipboardItem],
        cal: Calendar,
        cutoff: Date
    )
    -> [(date: Date, count: Int)] {
        let grouped = Dictionary(grouping: items) { cal.startOfDay(for: $0.timestamp) }
        let base = cal.startOfDay(for: cutoff)
        return (0..<range.days).compactMap { offset -> (Date, Int)? in
            guard let day = cal.date(byAdding: .day, value: offset, to: base) else { return nil }
            return (day, grouped[day]?.count ?? 0)
        }
    }

    private func buildTypeCounts(items: [ClipboardItem]) -> [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            counts[item.typeRaw, default: 0] += 1
        }
        return counts
            .map { (typeLabel($0.key), $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func buildTopPasted(items: [ClipboardItem]) -> [(preview: String, count: Int)] {
        items
            .filter { $0.pasteCount > 0 }
            .sorted { $0.pasteCount > $1.pasteCount }
            .prefix(10)
            .map { item in
                let preview = String(item.displayPreviewText.prefix(60))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (preview.isEmpty ? "—" : preview, item.pasteCount)
            }
    }

    private func buildTopSources(items: [ClipboardItem]) -> [SourceSummary] {
        var countByKey: [String: Int] = [:]
        var infoByKey: [String: String] = [:]
        for item in items {
            let key = item.sourceBundleID ?? "unknown"
            countByKey[key, default: 0] += 1
            if infoByKey[key] == nil {
                infoByKey[key] = item.sourceAppName ?? key
            }
        }
        return countByKey
            .map { key, count in
                SourceSummary(id: key, name: infoByKey[key] ?? key, count: count)
            }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map(\.self)
    }

    // MARK: - Helpers

    private func typeLabel(_ raw: String) -> String {
        switch raw {
        case "text": "Text"
        case "image": "Image"
        case "url": "URL"
        case "file": "File"
        case "color": "Color"
        case "code": "Code"
        default: raw.capitalized
        }
    }

    private func typeColor(_ label: String) -> Color {
        switch label {
        case "Text": .blue
        case "Image": .green
        case "URL": .orange
        case "File": .brown
        case "Color": .purple
        case "Code": .teal
        default: .gray
        }
    }
}

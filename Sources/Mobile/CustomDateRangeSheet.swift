// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct CustomDateRangeSheet: View {
    let initial: SearchDateFilter
    let onApply: (SearchDateFilter) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.pestoAccent) private var accent
    @State private var singleDay: Bool
    @State private var startDate: Date
    @State private var endDate: Date

    init(
        initial: SearchDateFilter,
        onApply: @escaping (SearchDateFilter) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.initial = initial
        self.onApply = onApply
        self.onClear = onClear
        if let interval = initial.interval(now: .now) {
            let lastDay = max(interval.start, min(Date.now, interval.end.addingTimeInterval(-1)))
            _startDate = State(initialValue: interval.start)
            _endDate = State(initialValue: lastDay)
            _singleDay = State(initialValue: Calendar.current.isDate(interval.start, inSameDayAs: lastDay))
        } else {
            _startDate = State(initialValue: .now)
            _endDate = State(initialValue: .now)
            _singleDay = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Single day", isOn: $singleDay)
                    DatePicker(
                        singleDay ? "Date" : "From",
                        selection: $startDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .onChange(of: startDate) { _, start in
                        if endDate < start {
                            endDate = start
                        }
                    }
                    if !singleDay {
                        DatePicker(
                            "To",
                            selection: $endDate,
                            in: startDate...Date.now,
                            displayedComponents: .date
                        )
                    }
                }
                if initial != .all {
                    Section {
                        Button("Clear Date Filter", role: .destructive) {
                            onClear()
                            dismiss()
                        }
                        .accessibilityIdentifier(MobileAccessibilityID.customDateClearButton)
                    }
                }
            }
            .tint(accent)
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(MobileAccessibilityID.customDateRangeSheet)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let end = singleDay ? startDate : endDate
                        onApply(SearchDateFilter.customRange(from: startDate, to: end))
                        dismiss()
                    }
                    .accessibilityIdentifier(MobileAccessibilityID.customDateApplyButton)
                }
            }
        }
    }
}

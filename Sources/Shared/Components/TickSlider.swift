// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// A slider with tick marks and a labelled tick at each recommended value, as Apple's guidelines suggest for a slider
/// whose values mean something. SwiftUI's `Slider` draws no ticks before macOS 26, so this wraps `NSSlider`. Letting go
/// near a tick lands on it.
struct TickSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let ticks: [Double]
    let snapTolerance: Double
    let label: String
    let identifier: String
    /// What each tick means ("Standard"), spoken after the number when the value sits on it.
    var tickNames: [Double: String] = [:]
    @Environment(\.pestoAccent) private var accent

    /// "190 points", or "190 points, Standard" when the value is on a named tick.
    static func spokenValue(_ value: Double, tickNames: [Double: String], tolerance: Double) -> String {
        let rounded = Int(value.rounded())
        let name = tickNames.min { abs($0.key - value) < abs($1.key - value) }
            .flatMap { abs($0.key - value) <= tolerance && !$0.value.isEmpty ? $0.value : nil }
        return name.map { "\(rounded) points, \($0)" } ?? "\(rounded) points"
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value, minValue: range.lowerBound, maxValue: range.upperBound,
            target: context.coordinator, action: #selector(Coordinator.changed(_:))
        )
        slider.numberOfTickMarks = ticks.count
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.setAccessibilityLabel(label)
        slider.setAccessibilityIdentifier(identifier)
        slider.trackFillColor = NSColor(accent)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.trackFillColor = NSColor(accent)
        if slider.doubleValue != value { slider.doubleValue = value }
        slider.toolTip = "\(Int(value.rounded())) pt"
        slider.setAccessibilityValueDescription(Self.spokenValue(value, tickNames: tickNames, tolerance: snapTolerance))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: TickSlider

        init(_ parent: TickSlider) {
            self.parent = parent
        }

        @MainActor @objc
        func changed(_ sender: NSSlider) {
            var next = sender.doubleValue.rounded()
            if NSApp.currentEvent?.type == .leftMouseUp, let tick = nearestTick(to: next) {
                next = tick
                sender.doubleValue = tick
            }
            parent.value = next
        }

        private func nearestTick(to value: Double) -> Double? {
            guard let tick = parent.ticks.min(by: { abs($0 - value) < abs($1 - value) }),
                  abs(tick - value) <= parent.snapTolerance else { return nil }
            return tick
        }
    }
}

/// The slider with its tick labels underneath, spread to match the ticks (first, middle and last for three).
struct LabelledTickSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let ticks: [(value: Double, label: String)]
    let snapTolerance: Double
    let accessibilityLabel: String
    let identifier: String

    var body: some View {
        VStack(spacing: 0) {
            TickSlider(
                value: $value, range: range, ticks: ticks.map(\.value), snapTolerance: snapTolerance,
                label: accessibilityLabel, identifier: identifier,
                tickNames: Dictionary(ticks.map { ($0.value, $0.label) }, uniquingKeysWith: { first, _ in first })
            )
            HStack(spacing: 0) {
                ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                    Text(tick.label)
                        .font(.caption)
                        .pestoQuiet()
                        .frame(maxWidth: .infinity, alignment: alignment(for: index))
                }
            }
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
        }
    }

    private func alignment(for index: Int) -> Alignment {
        if index == 0 { return .leading }
        return index == ticks.count - 1 ? .trailing : .center
    }
}

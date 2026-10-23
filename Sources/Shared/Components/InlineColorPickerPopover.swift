// SPDX-License-Identifier: MIT
import SwiftUI

/// An inline custom color picker popover with a 2D saturation/brightness square, a hue bar, and a hex field,
/// replacing the floating system `NSColorPanel`.
struct InlineColorPickerPopover: View {
    @Binding var hex: String
    var fallbackColor: Color
    var onPick: (String) -> Void = { _ in }

    @State private var hsb: HSBColor
    @State private var hexInput: String

    private static let fieldWidth: CGFloat = 192
    private static let fieldHeight: CGFloat = 128
    private static let hueBarHeight: CGFloat = 14

    init(hex: Binding<String>, fallbackColor: Color, onPick: @escaping (String) -> Void = { _ in }) {
        _hex = hex
        self.fallbackColor = fallbackColor
        self.onPick = onPick
        let initialHex = HSBColor(hex: hex.wrappedValue)?.hexString ?? fallbackColor.toHex() ?? "3D8B40"
        let resolvedHSB = HSBColor(hex: initialHex) ?? HSBColor(hue: 0.34, saturation: 0.56, brightness: 0.55)
        _hsb = State(initialValue: resolvedHSB)
        _hexInput = State(initialValue: "#" + resolvedHSB.hexString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            saturationBrightnessField
            hueSliderBar
            hexFieldRow
        }
        .padding(12)
        .frame(width: Self.fieldWidth + 24)
    }

    private var saturationBrightnessField: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hue: hsb.hue, saturation: 1, brightness: 1))
                .overlay {
                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                }

            Circle()
                .fill(hsb.color)
                .frame(width: 14, height: 14)
                .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .offset(
                    x: hsb.saturation * Self.fieldWidth - 7,
                    y: (1.0 - hsb.brightness) * Self.fieldHeight - 7
                )
        }
        .frame(width: Self.fieldWidth, height: Self.fieldHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let sat = min(max(value.location.x / Self.fieldWidth, 0), 1)
                    let bri = 1.0 - min(max(value.location.y / Self.fieldHeight, 0), 1)
                    hsb = HSBColor(hue: hsb.hue, saturation: sat, brightness: bri)
                    commitHSB()
                }
        )
    }

    private var hueSliderBar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: (0...6).map { Color(hue: Double($0) / 6.0, saturation: 1, brightness: 1) },
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                }

            Circle()
                .fill(Color(hue: hsb.hue, saturation: 1, brightness: 1))
                .frame(width: 14, height: 14)
                .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .offset(x: hsb.hue * (Self.fieldWidth - 14))
        }
        .frame(width: Self.fieldWidth, height: Self.hueBarHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let hue = min(max(value.location.x / Self.fieldWidth, 0), 1)
                    hsb = HSBColor(hue: hue, saturation: hsb.saturation, brightness: hsb.brightness)
                    commitHSB()
                }
        )
    }

    private var hexFieldRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(hsb.color)
                .frame(width: 22, height: 22)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1) }

            TextField("", text: $hexInput, prompt: Text("#3D8B40"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .scaledFont(size: 12, design: .monospaced)
                .onChange(of: hexInput) { _, newValue in
                    guard let parsed = HSBColor(hex: newValue), parsed.hexString != hsb.hexString else { return }
                    hsb = parsed
                    hex = parsed.hexString
                    onPick(parsed.hexString)
                }
        }
    }

    private func commitHSB() {
        let updated = hsb.hexString
        hexInput = "#" + updated
        hex = updated
        onPick(updated)
    }
}

// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The search page's keys (ADRs 0063, 0066): the letters of one of the person's own keyboards (`SearchKeyboardLayout`)
/// with Shift, caps lock and accents, or numbers and punctuation, and Delete where that layout puts it. They type into
/// Pesto's own search field and nowhere else: the only thing this view holds is the model, whose search methods change
/// only the query, and neither knows the app's text field (`KeyboardSearchTests` scans both).
struct KeyboardLetters: View {
    enum Layout: Equatable {
        case letters(SearchKeyboardLayout)
        case digits
    }

    enum Shift {
        case off
        case once
        case locked
    }

    let model: KeyboardModel
    let layout: Layout
    /// iPad puts Done at the end of the middle row, where Return is on its keyboard.
    var done: (() -> Void)?

    @State private var shift = Shift.off
    @State private var lastShiftTap: Date?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isRegular: Bool {
        sizeClass == .regular
    }

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var letterLayout: SearchKeyboardLayout? {
        if case let .letters(layout) = layout { return layout }
        return nil
    }

    private var rows: [[String]] {
        letterLayout?.rows ?? KeyboardPad.rows
    }

    private var deleteRow: Int {
        if isRegular { return 0 }
        return letterLayout?.deleteRow ?? rows.count - 1
    }

    private var showsShift: Bool {
        letterLayout?.hasShift ?? false
    }

    var body: some View {
        GeometryReader { geometry in
            let keyHeight = KeyboardSearchMetrics.keyHeight(
                rowCount: rows.count, isRegular: isRegular, isLandscape: isLandscape
            )
            let unit = unitWidth(available: geometry.size.width)
            VStack(spacing: KeyboardSearchMetrics.rowGap(isRegular: isRegular, isLandscape: isLandscape)) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: KeyboardSearchMetrics.keyGap(isRegular: isRegular)) {
                        if index == rows.count - 1, showsShift { shiftKey(width: unit * 1.4, height: keyHeight) }
                        ForEach(row, id: \.self) { key in
                            KeyboardLetterKey(
                                label: label(for: key),
                                variants: letterLayout?.variants(for: key, shifted: shift != .off) ?? [],
                                size: CGSize(width: unit, height: keyHeight),
                                showsCallout: !isRegular,
                                type: { typed in type(typed) }
                            )
                        }
                        if index == rows.count - 1, isRegular, showsShift {
                            shiftKey(width: unit * 1.4, height: keyHeight)
                        }
                        if index == deleteRow { deleteKey(width: unit * 1.4, height: keyHeight) }
                        if index == 1, isRegular, let done { doneKey(done, width: unit * 1.8, height: keyHeight) }
                    }
                    .frame(maxWidth: .infinity)
                    .zIndex(Double(index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: KeyboardSearchMetrics.letterAreaHeight(isRegular: isRegular, isLandscape: isLandscape))
        // Keycap rows follow physical keyboard order even when the interface direction is RTL.
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: layout) { _, _ in shift = .off }
    }

    private func label(for key: String) -> String {
        letterLayout?.label(for: key, shifted: shift != .off) ?? key
    }

    /// The width of one letter: as wide as a ten-letter row allows, narrower where a row has more keys (Thai,
    /// Arabic), and never wider, so a short row (Hebrew's eight) is centered rather than stretched.
    private func unitWidth(available: CGFloat) -> CGFloat {
        let gap = KeyboardSearchMetrics.keyGap(isRegular: isRegular)
        let usable = available - 6
        let standard = (usable - gap * 9) / 10
        let fitted = rows.indices.map { index -> CGFloat in
            let wide = wideKeys(inRow: index)
            let slots = rows[index].count + wide.count
            let units = CGFloat(rows[index].count) + wide.reduce(0, +)
            return (usable - gap * CGFloat(slots - 1)) / units
        }
        return max(16, min(([standard] + fitted).min() ?? standard, standard)).rounded(.down)
    }

    /// The widths, in letters, of the function keys that share a row with the letters.
    private func wideKeys(inRow index: Int) -> [CGFloat] {
        var widths: [CGFloat] = []
        if index == rows.count - 1, showsShift { widths.append(1.4) }
        if index == rows.count - 1, isRegular, showsShift { widths.append(1.4) }
        if index == deleteRow { widths.append(1.4) }
        if index == 1, isRegular, done != nil { widths.append(1.8) }
        return widths
    }

    private func type(_ typed: String) {
        model.typeInSearch(typed, composingHangul: letterLayout?.composesHangul ?? false)
        if shift == .once { shift = .off }
    }

    private func shiftKey(width: CGFloat, height: CGFloat) -> some View {
        Button {
            let now = Date()
            if let last = lastShiftTap, now.timeIntervalSince(last) < 0.35 {
                shift = .locked
            } else {
                shift = shift == .off ? .once : .off
            }
            lastShiftTap = now
        } label: {
            Image(systemName: shift == .locked ? "capslock.fill" : shift == .once ? "shift.fill" : "shift")
                .frame(width: width, height: height)
        }
        .buttonStyle(KeyboardKeyStyle(isFunction: shift == .off))
        .accessibilityLabel(shift == .locked ? Text("Caps Lock") : Text("Shift"))
        .accessibilityAddTraits(shift == .off ? [] : .isSelected)
    }

    private func deleteKey(width: CGFloat, height: CGFloat) -> some View {
        Button { model.deleteInSearch(decomposingHangul: letterLayout?.composesHangul ?? false) } label: {
            Image(systemName: "delete.left").frame(width: width, height: height)
        }
        .buttonStyle(KeyboardKeyStyle(isFunction: true))
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(Text("Delete"))
    }

    private func doneKey(_ action: @escaping () -> Void, width: CGFloat, height: CGFloat) -> some View {
        Button(action: action) {
            Text("Done").fontWeight(.semibold).frame(width: width, height: height)
        }
        .buttonStyle(KeyboardKeyStyle(isAccent: true))
    }

    static func resolvedLayouts(
        inputModeLanguages: [String] = UITextInputMode.activeInputModes.compactMap(\.primaryLanguage),
        preferredLanguages: [String] = Locale.preferredLanguages
    )
    -> [SearchKeyboardLayout] {
        SearchKeyboardLayout.resolved(inputModeLanguages: inputModeLanguages, preferredLanguages: preferredLanguages)
    }

    /// The person's keyboards a letter grid cannot type (Japanese, Chinese), named so the page can say so.
    static func inputMethodLanguages(
        inputModeLanguages: [String] = UITextInputMode.activeInputModes.compactMap(\.primaryLanguage)
    )
    -> [String] {
        inputModeLanguages.filter(SearchKeyboardLayout.needsInputMethod(languageCode:))
    }

    static func isInterfaceRTL(
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        preferredLanguages: [String] = Locale.preferredLanguages
    )
    -> Bool {
        let first = preferredLocalizations.first ?? preferredLanguages.first
        guard let first else { return false }
        return Locale.Language(identifier: first).characterDirection == .rightToLeft
    }

    static var isActiveLocaleRTL: Bool {
        isInterfaceRTL()
    }
}

// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What a keyboard card does, on the shelf and on the search page alike: a tap inserts (or copies a picture), a hold
/// does the other insert, a picture's menu copies it or inserts its text. Touches go through `KeyboardCardPress`, so a
/// card never holds up the row's scrolling.
struct KeyboardCardActions: ViewModifier {
    let entry: QuickInsertEntry
    let returnsAfterInsert: Bool
    let choose: (_ longPress: Bool) -> Void
    let useRecognizedText: (String) -> Void

    func body(content: Content) -> some View {
        if entry.kind == .image {
            content
                .gesture(KeyboardCardPress(tap: { choose(false) }))
                .contextMenu {
                    Button("Copy Picture", systemImage: "doc.on.doc") { choose(false) }
                    if let ocr = recognizedText {
                        Button("Insert Text", systemImage: "text.viewfinder") { useRecognizedText(ocr) }
                    }
                }
                .accessibilityAction { choose(false) }
                .accessibilityAction(named: Text("Insert Text")) {
                    if let ocr = recognizedText { useRecognizedText(ocr) }
                }
        } else {
            content
                .gesture(KeyboardCardPress(tap: { choose(false) }, hold: { choose(true) }))
                .accessibilityAction { choose(false) }
                .accessibilityAction(named: returnsAfterInsert ? Text("Insert and Stay") : Text("Insert and Return")) {
                    choose(true)
                }
        }
    }

    private var recognizedText: String? {
        guard let text = entry.recognizedText, !text.isEmpty else { return nil }
        return text
    }
}

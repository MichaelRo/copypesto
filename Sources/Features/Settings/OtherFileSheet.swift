// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The step between choosing a file of clips from an app Pesto has no reader for and the usual import preview: which
/// column is the text, when it was copied, what is pinned, or what one clip is in a text file. A column that is not
/// chosen is never read (`GenericFileMapping`).
struct OtherFileSheet: View {
    let fileName: String
    let file: GenericFile
    let onCancel: () -> Void
    let onContinue: (ClipboardAppLibrary) -> Void
    @State private var mapping: GenericFileMapping

    init(
        fileName: String, file: GenericFile,
        onCancel: @escaping () -> Void, onContinue: @escaping (ClipboardAppLibrary) -> Void
    ) {
        self.fileName = fileName
        self.file = file
        self.onCancel = onCancel
        self.onContinue = onContinue
        _mapping = State(initialValue: GenericFileMapping.detected(for: file))
    }

    private var library: ClipboardAppLibrary {
        GenericFileReader.library(from: file, mapping: mapping)
    }

    private var formatName: String {
        switch file.format {
        case .csv: "CSV file"
        case .json: "JSON file"
        case .text: "Text file"
        }
    }

    private var samples: [String] {
        library.records.prefix(3).compactMap { record in
            record.representations.first.flatMap { Data(base64Encoded: $0.dataBase64) }
                .flatMap { String(bytes: $0, encoding: .utf8) }
        }
    }

    var body: some View {
        let found = library
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from \(fileName)").font(.title3.weight(.semibold))
                .accessibilityIdentifier(AccessibilityID.otherFileSheet)
            Text("\(formatName). Check what Pesto found before importing.").pestoCaption()
            if file.format == .text {
                Picker("One clip is", selection: $mapping.separator) {
                    Text("A block between blank lines").tag(TextSeparator.blankLine)
                    Text("A single line").tag(TextSeparator.line)
                    Text("A block between lines of dashes").tag(TextSeparator.dashes)
                }
            } else {
                columnPicker("Text of the clip", selection: $mapping.textColumn)
                optionalColumnPicker("When it was copied", selection: $mapping.dateColumn)
                optionalColumnPicker("Keep as pinned", selection: $mapping.pinnedColumn)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    Text(sample).lineLimit(1).truncationMode(.tail).font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(summary(found)).font(.callout)
            Text("Text only. Secrets are masked as they would be on a copy, and clips you already have are skipped.")
                .pestoCaption()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Continue") { onContinue(found) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(found.records.isEmpty)
                    .accessibilityIdentifier(AccessibilityID.otherFileContinueButton)
            }
        }
        .padding(20)
        .frame(width: 470)
    }

    private func summary(_ found: ClipboardAppLibrary) -> String {
        guard found.skipped > 0 else { return CountText.clips(found.records.count) + "." }
        return CountText
            .clips(found.records.count) + ", " + String(localized: "\(found.skipped) left out (empty or too large).")
    }

    private func columnPicker(_ title: LocalizedStringKey, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(file.columns.enumerated()), id: \.offset) { index, name in
                Text(name.isEmpty ? "Column \(index + 1)" : name).tag(index)
            }
        }
    }

    private func optionalColumnPicker(_ title: LocalizedStringKey, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            Text("Not used").tag(Int?.none)
            ForEach(Array(file.columns.enumerated()), id: \.offset) { index, name in
                Text(name.isEmpty ? "Column \(index + 1)" : name).tag(Int?.some(index))
            }
        }
    }
}

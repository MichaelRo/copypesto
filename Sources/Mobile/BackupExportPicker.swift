// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

/// Files' own "save a copy" sheet for a backup written to the temporary folder: the person picks the folder (iCloud
/// Drive, On My iPhone, another provider), and Pesto keeps no bookmark to it.
struct BackupExportPicker: UIViewControllerRepresentable {
    let file: URL
    let onSaved: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSaved: onSaved, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSaved: () -> Void
        let onCancel: () -> Void

        init(onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.onSaved = onSaved
            self.onCancel = onCancel
        }

        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if urls.isEmpty { onCancel() } else { onSaved() }
        }

        func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

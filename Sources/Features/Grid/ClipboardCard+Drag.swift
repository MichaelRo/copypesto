// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drag provider

extension ClipboardCard {
    func makeItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        switch item.type {
        case .text, .code, .url, .color: registerText(on: provider)
        case .image: registerImage(on: provider)
        case .file: registerFiles(on: provider)
        }
        return provider
    }

    private func registerText(on provider: NSItemProvider) {
        let text: String = item.blob?.decryptedText() ?? item.displayPreviewText
        // A URL is offered as a URL first so browsers and link fields treat it as a hyperlink.
        if item.type == .url, let url = URL(string: text) {
            provider.registerObject(url as NSURL, visibility: .all)
        }
        for identifier in DragTypes.textIdentifiers {
            provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .all) { completion in
                completion(text.data(using: .utf8), nil)
                return nil
            }
        }
        // The Desktop and Finder windows take a file, not text data.
        let name = DragFile.fileName(title: item.customTitle, date: item.timestamp, fileExtension: "txt")
        registerFile(on: provider, type: UTType.plainText.identifier, name: name, data: Data(text.utf8))
    }

    private func registerImage(on provider: NSItemProvider) {
        guard let blob = item.blob, let imageData = blob.decryptedData() else { return }
        let name = DragFile.fileName(
            title: item.customTitle, date: item.timestamp,
            fileExtension: ImageExport.fileExtension(forUTI: blob.mimeType)
        )
        registerFile(on: provider, type: blob.mimeType, name: name, data: imageData)
        for identifier in DragTypes.imageIdentifiers(storedUTI: blob.mimeType) {
            let isStoredForm = identifier != UTType.png.identifier || blob.mimeType == UTType.png.identifier
            let isRenderedSVG = identifier == UTType.png.identifier && blob.mimeType == DragTypes.svg
            provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .all) { completion in
                if isRenderedSVG {
                    Task { @MainActor in completion(SVGThumbnail.png(from: imageData, maxPixel: 1024), nil) }
                } else {
                    completion(isStoredForm ? imageData : imageData.convertedToPNG(), nil)
                }
                return nil
            }
        }
    }

    private func registerFile(on provider: NSItemProvider, type: String, name: String, data: Data) {
        provider.registerFileRepresentation(forTypeIdentifier: type, fileOptions: [], visibility: .all) { completion in
            let file = DragFile.write(data, named: name)
            completion(file, false, file == nil ? CocoaError(.fileWriteUnknown) : nil)
            return nil
        }
    }

    private func registerFiles(on provider: NSItemProvider) {
        let urls = FileClip.urls(from: item.displayPreviewText)
        if let first = urls.first {
            provider.registerObject(first as NSURL, visibility: .all)
        }
        if !urls.isEmpty {
            let paths = urls.map(\.path)
            if let data = try? PropertyListSerialization.data(fromPropertyList: paths, format: .xml, options: 0) {
                provider.registerDataRepresentation(
                    forTypeIdentifier: DragTypes.filenamesPboardType,
                    visibility: .all
                ) { completion in
                    completion(data, nil)
                    return nil
                }
            }
        }
    }
}

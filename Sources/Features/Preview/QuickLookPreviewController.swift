// SPDX-License-Identifier: MIT
@preconcurrency import AppKit
import PestoCore
@preconcurrency import Quartz

/// Presents a system Quick Look panel for a `ClipboardItem`.
///
/// Decrypts the blob (if any) into a typed temp file, then delegates the panel
/// to that URL. Text items are written as `.txt`, images as the original MIME type.
/// The temp file lives for the duration of the panel session and is cleaned up on close.
@MainActor
final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var tempURL: URL?
    private var fileURLs: [URL] = []
    private weak var panel: QLPreviewPanel?
    private(set) var isOpen = false
    var onStateChanged: (@MainActor (Bool) -> Void)?
    var onClose: (@MainActor () -> Void)?

    func toggle(item: ClipboardItem) {
        if isOpen {
            close()
        } else {
            show(item: item)
        }
    }

    func show(item: ClipboardItem) {
        guard prepareFile(for: item) != nil else { return }

        let panel = QLPreviewPanel.shared()
        self.panel = panel
        isOpen = true
        onStateChanged?(true)
        panel?.dataSource = self
        panel?.delegate = self
        panel?.reloadData()
        panel?.makeKeyAndOrderFront(nil)
        fitToDisplay(panel)
    }

    /// The panel can leave without the will-close notification reaching this controller (its own Esc, or macOS
    /// handing the panel to another responder). A flag left on would reopen a preview at every arrow key, so the
    /// shelf asks before it relies on it.
    func reconcileWithPanel() {
        guard isOpen else { return }
        let visible = QLPreviewPanel.sharedPreviewPanelExists() && (panel?.isVisible ?? false)
        guard !visible else { return }
        markClosed()
    }

    private func markClosed() {
        let wasOpen = isOpen
        isOpen = false
        cleanup()
        if wasOpen {
            onStateChanged?(false)
            onClose?()
        }
    }

    private func fitToDisplay(_ panel: QLPreviewPanel?) {
        guard let panel, let visible = TargetScreen.current()?.visibleFrame else { return }
        panel.setFrame(QuickLookPanelSizing.frame(preferred: panel.frame.size, in: visible), display: true)
    }

    /// Closes the panel if it is showing this controller's clip and removes the decrypted file. The shelf calls it when
    /// it hides and when the history locks, so a decrypted clip does not stay on screen or in the temp folder.
    func close() {
        let wasOpen = isOpen
        isOpen = false
        if let panel, panel.dataSource === self {
            panel.orderOut(nil)
            panel.dataSource = nil
            panel.delegate = nil
        }
        cleanup()
        if wasOpen {
            onStateChanged?(false)
            onClose?()
        }
    }

    /// Writes the decrypted file the panel will show, or references the existing disk URLs if the clip is a file. Any
    /// file
    /// from an earlier preview is removed first, so at most one decrypted clip is on disk at a time.
    func prepareFile(for item: ClipboardItem) -> URL? {
        cleanup()
        if item.type == .file {
            let urls = FileClip.urls(from: item.displayPreviewText)
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !existing.isEmpty {
                fileURLs = existing
                return existing.first
            }
        }
        tempURL = buildTempFile(for: item)
        return tempURL
    }

    // MARK: - QLPreviewPanelDataSource

    // swiftlint:disable implicitly_unwrapped_optional

    nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            fileURLs.isEmpty ? 1 : fileURLs.count
        }
    }

    nonisolated func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            if !fileURLs.isEmpty, fileURLs.indices.contains(index) {
                return fileURLs[index] as (any QLPreviewItem)
            }
            return (tempURL as (any QLPreviewItem)?) ?? NSURL()
        }
    }

    // MARK: - QLPreviewPanelDelegate

    /// `QLPreviewPanelDelegate` has no "did close" callback; it inherits `NSWindowDelegate`, whose will-close is the
    /// one the panel really sends. (A `previewPanelDidClose` here was never called, and decrypted clips stayed in
    /// $TMPDIR.)
    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated { markClosed() }
    }

    nonisolated func previewPanel(_: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, event.keyCode == 53 else { return false }
        MainActor.assumeIsolated { close() }
        return true
    }

    // swiftlint:enable implicitly_unwrapped_optional

    /// The decrypted preview folders (and the files made for a drag to the Finder) are removed when the panel closes; a
    /// crash or force-quit leaves them behind,
    /// so launch removes any that remain.
    nonisolated static func sweepStaleTempFiles(in directory: URL = FileManager.default.temporaryDirectory) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names
            where name.hasPrefix("pesto-ql-") || name.hasPrefix(DragFile.folderPrefix)
            || (name.hasPrefix("Pesto event ") && name.hasSuffix(".ics"))
        {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: - Private

    private func buildTempFile(for item: ClipboardItem) -> URL? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-ql-\(item.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )

        if let blob = item.blob,
           let plain = blob.decryptedData()
        {
            let ext = QuickLookFileExtension.forTypeIdentifier(blob.mimeType)
            let url = tmp.appendingPathComponent("preview.\(ext)")
            FileManager.default.createFile(atPath: url.path, contents: plain, attributes: [.posixPermissions: 0o600])
            return url
        }

        // Fallback: plain-text preview.
        let url = tmp.appendingPathComponent("preview.txt")
        FileManager.default.createFile(
            atPath: url.path, contents: Data(item.displayPreviewText.utf8), attributes: [.posixPermissions: 0o600]
        )
        return url
    }

    private func cleanup() {
        fileURLs = []
        guard let url = tempURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
        tempURL = nil
    }
}

// SPDX-License-Identifier: MIT
import Foundation

/// Which click the card saw. `activate` is the accessibility action: one step, because a VoiceOver user cannot
/// double-click.
public enum ShelfClick: Equatable, Sendable {
    case single
    case double
    case activate
}

/// What a click on a card does (ADR 0009). A single click only moves focus, as in a list in Finder; a double click
/// pastes, so a stray click never sends text into another app. The shelf and the floating window share one grid, so the
/// choice is made here, where a test can reach it, and the view only acts on it. A double click arrives as a single
/// click first and then as a double, so a card that toggled on the first must be left alone by the second.
public enum ShelfTap: Equatable, Sendable {
    case copy
    case toggleSelection
    case focus
    case paste
    case ignore

    /// `pastesOnClick` is the floating window with auto-paste on: it stays open, so one click is the whole gesture.
    public static func route(
        copyOnly: Bool, pastesOnClick: Bool = false, hasSelection: Bool, extendsSelection: Bool, click: ShelfClick
    )
    -> ShelfTap {
        switch click {
        case .activate:
            if copyOnly { return .copy }
            return hasSelection ? .toggleSelection : .paste
        case .double:
            return copyOnly || pastesOnClick || hasSelection || extendsSelection ? .ignore : .paste
        case .single:
            if copyOnly { return .copy }
            if hasSelection || extendsSelection { return .toggleSelection }
            return pastesOnClick ? .paste : .focus
        }
    }
}

/// What a delete removes. The Delete key and a card's own Delete used to remove one clip even with several selected,
/// so a person who selected five and pressed Delete removed one and had to do it four more times.
public enum ShelfDeletion {
    /// The Delete key: the selection, or the focused clip when nothing is selected.
    public static func targets(selection: [UUID], focused: UUID?) -> [UUID] {
        if !selection.isEmpty { return selection }
        return focused.map { [$0] } ?? []
    }

    /// A card's menu: the selection when the card is part of a selection of several, otherwise that card alone.
    public static func targets(selection: [UUID], requestedFor card: UUID) -> [UUID] {
        selection.count > 1 && selection.contains(card) ? selection : [card]
    }
}

/// How a single-clip paste proceeds. The floating window stays on screen and pastes in place; the shelf closes first
/// and
/// the paste runs in its hide animation (`OverlayWindowController.hide(completion:)`).
public enum ShelfPaste: Equatable, Sendable {
    case ignore
    case inPlace
    case closeShelfThenPaste

    public static func route(isLocked: Bool, isPasting: Bool, pinnedWindow: Bool) -> ShelfPaste {
        if isLocked || isPasting { return .ignore }
        return pinnedWindow ? .inPlace : .closeShelfThenPaste
    }
}

public enum QuickPasteLast {
    /// Which history entry Quick Paste Last pastes: the one before what is on the clipboard now. That is the second
    /// clip, unless the clipboard holds a copy the history never kept (an excluded app, a concealed copy, a copy from
    /// another device with the setting off), in which case the newest clip is the previous one.
    public static func index(historyCount: Int, boardHoldsUnrecordedCopy: Bool) -> Int? {
        let index = boardHoldsUnrecordedCopy ? 0 : 1
        return historyCount > index ? index : nil
    }
}

public enum ClipText {
    /// The clip's whole text: its decrypted blob, or its preview when it has none (an old snippet).
    public static func full(of item: ClipboardItem) -> String {
        if let blob = item.blob, let text = blob.decryptedText() { return text }
        return item.displayPreviewText
    }
}

public enum ClipJoin {
    public struct Joined: Sendable {
        public let text: String
        public let isProtected: Bool
        public let leftOut: Int
    }

    /// Several clips joined by a blank line, protected (kept off Universal Clipboard) when any of them is a secret.
    /// Nil unless there are at least two. Paste All pastes this text; no clip is created. The text stops at
    /// `maxBytes`: a clip that would pass it, and every one after it, is left out and counted without being read
    /// (the size is stored with the clip), so selecting many large clips does not decrypt them all on the main thread.
    public static func join(
        _ items: [ClipboardItem], maxBytes: Int = ClipSizePolicy.maxTextBytes
    )
    -> Joined? {
        guard items.count > 1 else { return nil }
        var kept: [ClipboardItem] = []
        var total = 0
        for item in items {
            let separator = kept.isEmpty ? 0 : 2
            if !kept.isEmpty, total + separator + item.byteSize > maxBytes { break }
            total += separator + item.byteSize
            kept.append(item)
        }
        return Joined(
            text: kept.map(ClipText.full(of:)).joined(separator: "\n\n"),
            isProtected: kept.contains { $0.sensitivityRaw != nil },
            leftOut: items.count - kept.count
        )
    }
}

public extension PasteStack.Item {
    /// A stack item made from a clip without touching the pasteboard: the blob is decrypted now, so everything the
    /// stack will paste is captured when it is made.
    init(clip item: ClipboardItem) {
        let display = item.displayPreviewText
        let isText = item.type == .text || item.type == .code
        if let blob = item.blob, let plaintext = blob.decryptedData() {
            let rich = blob.decryptedRichPayload()
            let textString = String(data: plaintext, encoding: .utf8) ?? display
            let payloadKind: PasteCoordinator.PayloadKind = if !isText {
                .nonText
            } else if rich != nil {
                .richText(textString)
            } else {
                .text(textString)
            }
            self.init(
                previewText: display,
                payloadKind: payloadKind,
                pasteboardData: plaintext,
                pasteboardType: blob.mimeType,
                richPayload: rich,
                isProtected: item.sensitivityRaw != nil
            )
        } else {
            self.init(
                previewText: display, payloadKind: isText ? .text(display) : .nonText,
                isProtected: item.sensitivityRaw != nil
            )
        }
    }
}

// SPDX-License-Identifier: MIT
import Foundation

/// The icons a collection offers, each with the word VoiceOver says for it ("Tray", not "tray.full").
public enum CollectionSymbols {
    public static let choices: [(symbol: String, name: String)] = [
        ("tray.full", "Tray"), ("star", "Star"), ("heart", "Heart"), ("bookmark", "Bookmark"), ("tag", "Tag"),
        ("folder", "Folder"), ("doc", "Document"), ("link", "Link"), ("photo", "Photo"), ("paperclip", "Paperclip"),
        ("pencil", "Pencil"), ("highlighter", "Highlighter"), ("scissors", "Scissors"), ("archivebox", "Archive box"),
        ("externaldrive", "Drive"), ("globe", "Globe"), ("safari", "Compass"), ("envelope", "Envelope"),
        ("message", "Message"), ("bubble.left", "Speech bubble"), ("calendar", "Calendar"), ("clock", "Clock"),
        ("alarm", "Alarm"), ("bolt", "Lightning bolt"), ("flame", "Flame"), ("leaf", "Leaf"), ("tree", "Tree"),
        ("mountain.2", "Mountains"), ("drop", "Drop"), ("cloud", "Cloud")
    ]

    public static var symbols: [String] {
        choices.map(\.symbol)
    }

    public static func name(for symbol: String) -> String {
        choices.first { $0.symbol == symbol }?.name ?? symbol
    }
}

// SPDX-License-Identifier: MIT

/// The groups of a card's context menu, so the menu of a covered card is one tested list (ADR 0028) rather than a
/// condition on each item.
public enum CardMenuItem: CaseIterable, Sendable {
    case paste
    case pastePlain
    case copy
    case copyLinkPreview
    case copyRecognizedText
    case quickLook
    case revealSecret
    case decodeJWT
    case saveImage
    case colorCopyFormats
    case openLink
    case showInFinder
    case moveToCollection
    case pin
    case rename
    case note
    case icon
    case tag
    case clearCustomizations
    case copyTransformed
    case pasteTransformed
    case entityActions
    case aiActions
    case markSensitive
    case setExpiry
    case assignShortcut
    case delete

    /// What a card covered for a screen share still offers: paste it, copy it, show it (its own Show, outside this
    /// list) and delete it. Anything that names the content, its pin, title, note, tags, collection, expiry or shortcut
    /// is left out.
    public static let coveredAllowed: Set<CardMenuItem> = [.paste, .pastePlain, .copy, .delete]

    public func isOffered(covered: Bool) -> Bool {
        !covered || Self.coveredAllowed.contains(self)
    }
}

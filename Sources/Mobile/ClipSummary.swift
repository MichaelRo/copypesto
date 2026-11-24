// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// What a row says about a clip: its main line, a second line where the kind has one, and where it came from. A
/// covered clip says only its mask or its kind, never its content.
struct ClipSummary: Equatable {
    enum Visual: Equatable {
        case symbol(String)
        case picture
        case swatch(HexColorComponents)
    }

    let title: String
    let detail: String?
    let source: String?
    let visual: Visual
    let isPinned: Bool
    let isCovered: Bool

    @MainActor
    static func make(
        _ item: ClipboardItem,
        concealment: CardConcealment,
        coveredForPrivacy: Bool = false,
        peerDeviceNames: [String: String] = [:]
    )
    -> ClipSummary {
        let covered = concealment.isConcealed
        let type = item.type
        let origin = CardFootLine.origin(of: item, peerDeviceNames: peerDeviceNames)
        let source = item.isRemote
            ? (origin.deviceName ?? String(localized: "Another device"))
            : (item.knownSourceAppName ?? origin.deviceName)
        if covered {
            let masked = item.sensitivityRaw != nil && !coveredForPrivacy
            let title = masked ? item.gridPreview : coveredTitle(for: type, item: item)
            return ClipSummary(
                title: title, detail: masked ? item.sensitivity?.badgeLabel : nil,
                source: coveredForPrivacy ? nil : source,
                visual: .symbol(masked ? "lock" : "eye.slash"), isPinned: item.isPinned,
                isCovered: true
            )
        }
        let preview = item.gridPreview
        let custom = item.customTitle.flatMap { $0.isEmpty ? nil : $0 }
        switch type {
        case .url:
            let host = LinkDisplay.parse(preview)?.host
            let title = custom ?? item.ogTitle ?? host ?? preview
            let address = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = item.ogTitle != nil || custom != nil ? item.ogSiteName ?? host ?? address : address
            return ClipSummary(
                title: title, detail: detail == title ? nil : detail, source: source,
                visual: .symbol(type.presentation.symbolName), isPinned: item.isPinned, isCovered: false
            )
        case .image:
            let size = item.pixelWidth.flatMap { width in item.pixelHeight.map { "\(width) × \($0)" } }
            return ClipSummary(
                title: custom ?? String(localized: "Picture"), detail: size, source: source, visual: .picture,
                isPinned: item.isPinned, isCovered: false
            )
        case .color:
            let visual: Visual = ColorLiteralParser.color(fromWholeString: preview).map(Visual.swatch)
                ?? .symbol(type.presentation.symbolName)
            return ClipSummary(
                title: custom ?? preview, detail: nil, source: source, visual: visual, isPinned: item.isPinned,
                isCovered: false
            )
        case .file:
            let files = FileClip.summary(of: preview)
            return ClipSummary(
                title: custom ?? files.title, detail: files.subtitle.isEmpty ? nil : files.subtitle, source: source,
                visual: .symbol(type.presentation.symbolName), isPinned: item.isPinned, isCovered: false
            )
        case .text, .code:
            return ClipSummary(
                title: custom ?? preview, detail: custom == nil ? nil : preview, source: source,
                visual: .symbol(type.presentation.symbolName), isPinned: item.isPinned, isCovered: false
            )
        }
    }

    private static func coveredTitle(for type: ClipboardType, item: ClipboardItem) -> String {
        if item.analysisPending { return String(localized: "Checking this clip") }
        return type == .image ? String(localized: "Hidden picture") : String(localized: "Hidden clip")
    }
}

// SPDX-License-Identifier: MIT
import Foundation

/// Another clipboard manager whose history Pesto can bring in, and the bundle identifiers that say it is installed.
/// Finding an install by identifier asks LaunchServices where the app is; it never opens the app's own data, which
/// macOS guards with a privacy prompt.
public enum ImportSource: String, CaseIterable, Sendable {
    case paste
    case maccy
    case alfred
    case cleanclip
    case pastenow
    case copyclip
    case pastepal
    case pastebot
    case clipy
    case flycut
    case unclutter

    public var name: String {
        switch self {
        case .paste: "Paste"
        case .maccy: "Maccy"
        case .alfred: "Alfred"
        case .cleanclip: "CleanClip"
        case .pastenow: "PasteNow"
        case .copyclip: "CopyClip"
        case .pastepal: "PastePal"
        case .pastebot: "Pastebot"
        case .clipy: "Clipy"
        case .flycut: "Flycut"
        case .unclutter: "Unclutter"
        }
    }

    /// The direct and Setapp builds of Paste have their own identifiers.
    public var bundleIDs: [String] {
        switch self {
        case .paste: ["com.wiheads.paste", "com.wiheads.paste-setapp"]
        case .maccy: ["org.p0deje.Maccy"]
        case .alfred: ["com.runningwithcrayons.Alfred"]
        case .cleanclip: ["com.antiless.cleanclip.mac"]
        case .pastenow: ["app.pastenow.PasteNow"]
        case .copyclip: ["com.fiplab.clipboard", "com.fiplab.copyclip"]
        case .pastepal: ["com.onmyway133.PastePal", "com.cmhaertling.PastePal"]
        case .pastebot: ["com.tapbots.Pastebot3Mac", "com.tapbots.PastebotMac"]
        case .clipy: ["com.clipy-app.Clipy"]
        case .flycut: ["com.generalarcade.flycut"]
        case .unclutter: ["com.softwareambience.Unclutter"]
        }
    }
}

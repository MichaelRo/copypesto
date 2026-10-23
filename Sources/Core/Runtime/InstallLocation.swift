// SPDX-License-Identifier: MIT
import Foundation

/// Where this copy of Pesto is running from, and whether to offer to move it to Applications. Launch Pesto at login,
/// updates
/// and the Accessibility grant all want one stable, installed copy, and a copy opened straight from a disk image or the
/// Downloads folder is the one people forget to move.
public enum InstallLocation: Equatable {
    public enum Source: Equatable {
        case diskImage
        case downloads
        case elsewhere
    }

    case installed
    case development
    case offerMove(Source)

    /// Why macOS would not register this copy as a login item, which depends on where it is: only an app in the
    /// Applications folder can be.
    public var launchAtLoginUnavailableExplanation: String {
        switch self {
        case .installed:
            "macOS did not accept Pesto as a login item. Add it under System Settings \u{2192} Login Items."
        case .development:
            "This is a development copy, which macOS cannot register. "
                + "Launch Pesto at login works for the installed copy of Pesto."
        case .offerMove:
            "Launch Pesto at login is not available for this copy of Pesto. macOS can only register an app that is "
                + "installed in your Applications folder: move Pesto there and open it from there."
        }
    }

    public static func evaluate(bundlePath: String, home: String = NSHomeDirectory()) -> InstallLocation {
        if bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix("\(home)/Applications/") {
            return .installed
        }
        // A build from the repo or Xcode is run in place on purpose.
        if ["/.build/", "/DerivedData/", "/Build/Products/"].contains(where: bundlePath.contains) {
            return .development
        }
        if bundlePath.hasPrefix("/Volumes/") { return .offerMove(.diskImage) }
        // macOS runs a quarantined app from a read-only copy of where it was; the original folder is not known.
        if bundlePath.contains("/AppTranslocation/") || bundlePath.hasPrefix("\(home)/Downloads/") {
            return .offerMove(.downloads)
        }
        return .offerMove(.elsewhere)
    }
}

public enum AppInstallerError: Error, Equatable {
    case couldNotReplace
    case couldNotCopy
}

/// Copies an app bundle into a folder, replacing an older copy there by moving it to the Trash first.
public enum AppInstaller {
    /// The folder to install into: Applications when this person can write to it, otherwise their own Applications.
    public static func destinationFolder(fileManager: FileManager = .default, home: URL = URL(
        fileURLWithPath: NSHomeDirectory(),
        isDirectory: true
    ))
    -> URL {
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if fileManager.isWritableFile(atPath: system.path) { return system }
        return home.appendingPathComponent("Applications", isDirectory: true)
    }

    public static func install(bundle: URL, into folder: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(bundle.lastPathComponent, isDirectory: true)
        if destination.standardizedFileURL == bundle.standardizedFileURL { return destination }
        if fileManager.fileExists(atPath: destination.path) {
            do {
                try fileManager.trashItem(at: destination, resultingItemURL: nil)
            } catch {
                throw AppInstallerError.couldNotReplace
            }
        }
        do {
            try fileManager.copyItem(at: bundle, to: destination)
        } catch {
            throw AppInstallerError.couldNotCopy
        }
        return destination
    }
}

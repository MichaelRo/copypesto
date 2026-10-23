// SPDX-License-Identifier: MIT
import Foundation

public enum AppIdentity {
    public static let bundleID = "net.copypesto.pesto"
    public static let legacyBundleID = "io.pesto.app"

    public static let controlsBundleID = "\(bundleID).controls"
    public static let cliBundleID = "\(bundleID).cli"

    public static let logSubsystem = bundleID
    public static let supportDirectoryName = bundleID
    public static let keychainService = bundleID
    public static let blobKeyAccount = "\(bundleID).blobKey"
    public static let deviceIDAccount = "\(bundleID).deviceID"

    public static let legacySupportDirectoryName = legacyBundleID
    public static let legacyKeychainService = legacyBundleID
    public static let legacyBlobKeyAccount = "\(legacyBundleID).blobKey"
    public static let legacySpotlightDomain = "\(legacyBundleID).clips"

    public static func notificationName(_ name: String) -> Notification.Name {
        Notification.Name("\(bundleID).\(name)")
    }
}

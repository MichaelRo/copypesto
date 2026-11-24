// SPDX-License-Identifier: MIT
import Foundation

public enum AppIdentity {
    public static let bundleID = "net.copypesto.pesto"
    public static let legacyBundleID = "io.pesto.app"

    public static let controlsBundleID = "\(bundleID).controls"
    public static let cliBundleID = "\(bundleID).cli"
    public static let shareBundleID = "\(bundleID).share"
    public static let appGroupID = "group.\(bundleID)"
    /// The iOS app's background refresh for sync; the same string is in `PestoMobile-Info.plist`.
    public static let syncRefreshTaskID = "\(bundleID).sync-refresh"

    public static let logSubsystem = bundleID
    public static let supportDirectoryName = bundleID
    public static let keychainService = bundleID
    public static let blobKeyAccount = "\(bundleID).blobKey"
    public static let deviceIDAccount = "\(bundleID).deviceID"
    public static let inboxKeyAccount = "\(bundleID).inboxKey"
    public static let inboxDirectoryName = "inbox"
    public static let inboxPublicKeyFileName = "inbox-key.pestokey"
    public static let inboxFileExtension = "pestoinbox"
    public static let autofillBundleID = "\(bundleID).autofill"
    public static let keyboardBundleID = "\(bundleID).keyboard"
    public static let quickInsertKeyAccount = "\(bundleID).quickInsertKey"
    public static let quickInsertFileName = "quick-insert.pestoquick"
    /// The Keychain group the iOS app, its AutoFill extension and its keyboard share, after the team prefix their
    /// entitlements files name as `$(AppIdentifierPrefix)` (ADRs 0051, 0061).
    public static let quickInsertKeychainGroupName = "\(bundleID).quick-insert"
    /// The Info.plist key both iOS bundles carry `$(AppIdentifierPrefix)` in, so the code knows the group's full name.
    public static let appIdentifierPrefixInfoKey = "PestoAppIdentifierPrefix"

    public static func quickInsertKeychainGroup(prefix: String) -> String {
        prefix + quickInsertKeychainGroupName
    }

    public static func quickInsertKeychainGroup(in bundle: Bundle) -> String {
        quickInsertKeychainGroup(prefix: appIdentifierPrefix(in: bundle))
    }

    /// The scheme of `pesto://` links: the Mac's automation links and the iOS widget's links to a clip (ADR 0052).
    public static let urlScheme = "pesto"
    public static let widgetBundleID = "\(bundleID).widget"
    /// The kind of the iOS Recent Clips widget, which the app names when it reloads its timelines.
    public static let widgetKind = "\(bundleID).recent-clips"
    /// The kind of the iOS Lock Screen accessory widget (ADR 0065).
    public static let lockScreenWidgetKind = "\(bundleID).lock-screen-clips"
    public static let widgetKinds = [widgetKind, lockScreenWidgetKind]
    public static let widgetKeyAccount = "\(bundleID).widgetKey"
    public static let widgetSnapshotFileName = "widget-snapshot.pestowidget"
    /// The Keychain group the iOS app and its widget share (ADR 0052), after the team prefix.
    public static let widgetKeychainGroupName = "\(bundleID).widget"

    public static func widgetKeychainGroup(prefix: String) -> String {
        prefix + widgetKeychainGroupName
    }

    public static func widgetKeychainGroup(in bundle: Bundle) -> String {
        widgetKeychainGroup(prefix: appIdentifierPrefix(in: bundle))
    }

    private static func appIdentifierPrefix(in bundle: Bundle) -> String {
        bundle.object(forInfoDictionaryKey: appIdentifierPrefixInfoKey) as? String ?? ""
    }

    public static let legacySupportDirectoryName = legacyBundleID
    public static let legacyKeychainService = legacyBundleID
    public static let legacyBlobKeyAccount = "\(legacyBundleID).blobKey"
    public static let legacySpotlightDomain = "\(legacyBundleID).clips"

    public static func notificationName(_ name: String) -> Notification.Name {
        Notification.Name("\(bundleID).\(name)")
    }
}

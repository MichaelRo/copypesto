// SPDX-License-Identifier: MIT
import Foundation

/// Where Pesto keeps its data. Tests get a session-scoped temporary directory so a run never opens
/// or overwrites the user's real store, whatever environment the runner provides.
public enum AppPaths {
    public static var supportDirectory: URL {
        supportDirectory(
            for: RuntimeConfiguration.current,
            applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            temporary: FileManager.default.temporaryDirectory
        )
    }

    static func supportDirectory(
        for configuration: RuntimeConfiguration,
        applicationSupport: URL,
        temporary: URL
    )
    -> URL {
        guard configuration.mode != .normal else {
            return applicationSupport.appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
        }
        return configuration.directory
            ?? temporary.appendingPathComponent("io.pesto.uitest.\(configuration.session)", isDirectory: true)
    }

    /// The app group the iOS app shares with its extensions (ADR 0047); a test or UI-test launch gets a folder inside
    /// its own support folder. On the Mac only a build signed for the widget has it (`WidgetSharing`, ADR 0059): any
    /// other Mac build gets nil without asking for the container, which macOS 15 would answer with a prompt.
    public static var sharedGroupDirectory: URL? {
        let configuration = RuntimeConfiguration.current
        guard configuration.mode == .normal || configuration.usesRealQuickInsert else {
            return sharedGroupDirectory(
                for: configuration, groupContainer: nil,
                applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                temporary: FileManager.default.temporaryDirectory
            )
        }
        #if os(macOS)
        guard WidgetSharing.current != nil else { return nil }
        #endif
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroupID)
    }

    static func sharedGroupDirectory(
        for configuration: RuntimeConfiguration, groupContainer: URL?, applicationSupport: URL, temporary: URL
    )
    -> URL? {
        guard configuration.mode != .normal else { return groupContainer }
        return supportDirectory(for: configuration, applicationSupport: applicationSupport, temporary: temporary)
            .appendingPathComponent("Group", isDirectory: true)
    }

    /// Where Save Image puts a file: the person's Downloads folder, and inside the session's temporary folder for a
    /// test run, so a test never writes to the real one.
    public static var downloadsDirectory: URL {
        downloadsDirectory(
            for: RuntimeConfiguration.current,
            downloads: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
            applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            temporary: FileManager.default.temporaryDirectory
        )
    }

    static func downloadsDirectory(
        for configuration: RuntimeConfiguration,
        downloads: URL,
        applicationSupport: URL,
        temporary: URL
    )
    -> URL {
        guard configuration.mode != .normal else { return downloads }
        return supportDirectory(for: configuration, applicationSupport: applicationSupport, temporary: temporary)
            .appendingPathComponent("Downloads", isDirectory: true)
    }
}

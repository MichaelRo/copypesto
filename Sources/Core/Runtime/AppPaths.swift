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

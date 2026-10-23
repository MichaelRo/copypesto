// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Install location")
struct InstallLocationTests {
    private let home = "/Users/sam"

    @Test("a copy in Applications, or in the person's own Applications, is installed", arguments: [
        "/Applications/Pesto.app", "/Users/sam/Applications/Pesto.app", "/Applications/Utilities/Pesto.app"
    ])
    func installed(path: String) {
        #expect(InstallLocation.evaluate(bundlePath: path, home: home) == .installed)
    }

    @Test("a build from the repo or Xcode is left where it is", arguments: [
        "/Users/sam/Projects/Clipboard/.build/xcode/Build/Products/Debug/Pesto.app",
        "/Users/sam/Library/Developer/Xcode/DerivedData/Pesto-abc/Build/Products/Debug/Pesto.app"
    ])
    func development(path: String) {
        #expect(InstallLocation.evaluate(bundlePath: path, home: home) == .development)
    }

    @Test(
        "a copy opened from a disk image, the Downloads folder, a translocated path or anywhere else is offered a move"
    )
    func offered() {
        #expect(InstallLocation.evaluate(bundlePath: "/Volumes/Pesto/Pesto.app", home: home) == .offerMove(.diskImage))
        #expect(
            InstallLocation.evaluate(bundlePath: "/Users/sam/Downloads/Pesto.app", home: home)
                == .offerMove(.downloads)
        )
        #expect(
            InstallLocation.evaluate(
                bundlePath: "/private/var/folders/x/T/AppTranslocation/ABC/d/Pesto.app", home: home
            ) == .offerMove(.downloads)
        )
        #expect(
            InstallLocation.evaluate(bundlePath: "/Users/sam/Desktop/Pesto.app", home: home) == .offerMove(.elsewhere)
        )
    }
}

@Suite("App installer")
struct AppInstallerTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-installer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func fakeApp(in folder: URL, marker: String) throws -> URL {
        let app = folder.appendingPathComponent("Pesto.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true
        )
        try Data(marker.utf8).write(to: app.appendingPathComponent("Contents/marker.txt"))
        return app
    }

    @Test("the bundle is copied into the folder, which is made if it is missing")
    func copies() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fakeApp(in: root.appendingPathComponent("disk", isDirectory: true), marker: "new")
        let target = root.appendingPathComponent("Applications", isDirectory: true)

        let installed = try AppInstaller.install(bundle: source, into: target)

        #expect(installed.path == target.appendingPathComponent("Pesto.app").path)
        #expect(try String(contentsOf: installed.appendingPathComponent("Contents/marker.txt"), encoding: .utf8) ==
            "new")
        #expect(FileManager.default.fileExists(atPath: source.path), "the source is copied, not moved")
    }

    @Test("an older copy there is replaced, not merged into")
    func replaces() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Applications", isDirectory: true)
        let older = try fakeApp(in: target, marker: "old")
        try Data("stale".utf8).write(to: older.appendingPathComponent("Contents/leftover.txt"))
        let source = try fakeApp(in: root.appendingPathComponent("disk", isDirectory: true), marker: "new")

        let installed = try AppInstaller.install(bundle: source, into: target)

        #expect(try String(contentsOf: installed.appendingPathComponent("Contents/marker.txt"), encoding: .utf8) ==
            "new")
        #expect(!FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/leftover.txt").path))
    }

    @Test("a copy already in the folder is left alone")
    func alreadyThere() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Applications", isDirectory: true)
        let app = try fakeApp(in: target, marker: "same")

        let installed = try AppInstaller.install(bundle: app, into: target)

        #expect(installed.path == app.path)
        #expect(try String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8) == "same")
    }

    @Test("the launch-at-login caption names the real cause: where this copy lives")
    func launchAtLoginExplanation_followsTheInstallLocation() {
        let installed = InstallLocation.installed.launchAtLoginUnavailableExplanation
        let development = InstallLocation.development.launchAtLoginUnavailableExplanation
        let downloaded = InstallLocation.offerMove(.downloads).launchAtLoginUnavailableExplanation

        #expect(installed.contains("System Settings"), "an installed copy is not told to move")
        #expect(!installed.contains("move Pesto"))
        #expect(development.contains("development"))
        #expect(downloaded.contains("Applications folder"))
        #expect(Set([installed, development, downloaded]).count == 3)
    }
}

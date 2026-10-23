// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

extension AppDelegate {
    private static let diskImageExplanation = String(localized: """
    Pesto will copy itself to Applications, open the copy and eject the disk image. \
    Launch Pesto at login, updates and the paste permission all need one installed copy.
    """)

    private static let downloadsExplanation = String(localized: """
    Pesto will copy itself to Applications and open the copy. \
    Launch Pesto at login, updates and the paste permission all need one installed copy.
    """)

    /// Offers to move a copy that was opened from a disk image or the Downloads folder into Applications, then opens
    /// that copy and quits. Returns true when the app is on its way out. Normal launches only.
    @discardableResult
    func offerToMoveToApplicationsIfNeeded() -> Bool {
        let path = Bundle.main.bundleURL.path
        guard !AppDefaults.store.value(for: Setting.installPromptSuppressed),
              case let .offerMove(source) = InstallLocation.evaluate(bundlePath: path) else { return false }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Move Pesto to your Applications folder?")
        alert.informativeText = source == .diskImage ? Self.diskImageExplanation : Self.downloadsExplanation
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don\u{2019}t ask again")
        let answer = alert.runModal()
        if alert.suppressionButton?
            .state == .on { AppDefaults.store.set(true, for: Setting.installPromptSuppressed) }
        guard answer == .alertFirstButtonReturn else { return false }
        return moveToApplications(from: source)
    }

    private func moveToApplications(from source: InstallLocation.Source) -> Bool {
        do {
            let installed = try AppInstaller.install(
                bundle: Bundle.main.bundleURL, into: AppInstaller.destinationFolder()
            )
            if source == .diskImage { ejectDiskImageSoon() }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: installed, configuration: configuration) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Pesto could not be moved")
            alert
                .informativeText =
                String(localized: "Drag Pesto into your Applications folder in Finder, then open it from there.")
            alert.runModal()
            return false
        }
    }

    /// The disk image holds this running copy, so it can only be ejected once the app has quit.
    private func ejectDiskImageSoon() {
        let parts = Bundle.main.bundleURL.pathComponents
        guard parts.count > 2, parts[1] == "Volumes" else { return }
        let volume = "/Volumes/\(parts[2])"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 3; /usr/bin/hdiutil detach \"$0\" -quiet", volume]
        try? task.run()
    }
}

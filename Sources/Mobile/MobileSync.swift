// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore
import SwiftData

/// Sync on an iPhone or iPad (ADR 0046): the folder the person picked, held open while the app is in front, and Core's
/// `SyncController` on it. Exchanges run on turning sync on, at launch, on each return to the foreground, when the
/// folder reports a change, on the controller's poll, on pull to refresh and in a background refresh (`SyncExchange`).
@MainActor
@Observable
final class MobileSync {
    struct Environment {
        var folder: any SyncFolderSource
        var deviceKind: SyncDeviceKind
        var defaults: UserDefaults
        var authenticator: any UserAuthenticating
        var grace: AuthenticationGrace
        var makeController: @MainActor (URL) -> SyncController?
    }

    private(set) var controller: SyncController?
    private(set) var folderProblem: SyncFolderProblem?
    private(set) var hasFolder = false
    @ObservationIgnored private let env: Environment

    init(_ environment: Environment) {
        env = environment
        hasFolder = environment.folder.hasChosenFolder
    }

    var deviceKind: SyncDeviceKind {
        env.deviceKind
    }

    var isEnabled: Bool {
        controller?.isEnabled ?? false
    }

    var status: MobileSyncStatus {
        MobileSyncStatus(
            folderProblem: folderProblem, isEnabled: isEnabled, status: controller?.status, device: env.deviceKind
        )
    }

    var flow: SyncFlow {
        controller?.flow ?? .idle
    }

    var pendingJoin: SyncPendingJoin? {
        controller?.pendingJoin
    }

    var keyMode: SyncKeyMode? {
        controller?.keyMode
    }

    var folderName: String? {
        guard folderProblem == nil, let url = controller?.folderURL else { return nil }
        let parent = FileManager.default.displayName(atPath: url.deletingLastPathComponent().path)
        return [parent, url.lastPathComponent].joined(separator: " \u{203A} ")
    }

    // MARK: The folder and the app's life

    /// Who holds the folder open: the app in front, a background refresh, or both. The folder is let go only when the
    /// last of them is done, so a background refresh that ends after the app came back leaves sync running.
    enum Holder: Hashable {
        case foreground
        case background
    }

    @ObservationIgnored private var holders: Set<Holder> = []

    func activate(for holder: Holder = .foreground) {
        holders.insert(holder)
        applyResolution(env.folder.resolve())
    }

    func activateAsync(for holder: Holder = .foreground) async {
        holders.insert(holder)
        let resolution = await env.folder.resolveAsync()
        applyResolution(resolution)
    }

    private func applyResolution(_ resolution: SyncFolderResolution) {
        switch resolution {
        case .notChosen:
            hasFolder = false
            folderProblem = nil
        case let .needsRepair(problem):
            hasFolder = true
            folderProblem = problem
            controller?.suspend()
        case let .ready(root):
            hasFolder = true
            folderProblem = nil
            if let controller {
                if !Self.isSameFolder(controller.folderURL, root) { controller.chooseFolder(root) }
            } else {
                controller = env.makeController(root)
            }
            controller?.resumeIfEnabled()
        }
    }

    func deactivate(for holder: Holder = .foreground) {
        holders.remove(holder)
        guard holders.isEmpty else { return }
        controller?.suspend()
        env.folder.relinquish()
    }

    /// The folder the person picked. The same folder again (a repair) keeps sync where it was; another folder is a
    /// move, which stops sync here, leaves the old folder alone and offers set-up in the new one, as on a Mac.
    func useFolder(_ picked: URL) {
        let root: URL
        do {
            root = try env.folder.choose(picked)
        } catch {
            folderProblem = .unreachable
            return
        }
        hasFolder = true
        folderProblem = nil
        let previous = controller?.folderURL.path ?? env.defaults.value(for: Setting.syncFolderPath)
        guard let current = controller ?? env.makeController(root) else { return }
        controller = current
        if previous.isEmpty || Self.isSameFolder(URL(fileURLWithPath: previous, isDirectory: true), root) {
            current.chooseFolder(root)
            if current.isEnabled { current.resumeIfEnabled() } else { current.beginSetUp() }
        } else {
            current.changeFolder(to: root)
        }
    }

    /// Whether sync can start from the folder already chosen, rather than asking for one first.
    var canBeginSetUp: Bool {
        hasFolder && folderProblem == nil && controller != nil
    }

    func beginSetUp() {
        controller?.beginSetUp()
    }

    static func isSameFolder(_ one: URL, _ other: URL) -> Bool {
        one.standardizedFileURL.resolvingSymlinksInPath().path
            == other.standardizedFileURL.resolvingSymlinksInPath().path
    }

    // MARK: Turning on and joining

    func turnOn() async {
        await controller?.turnOn()
    }

    func confirmJoin() {
        controller?.confirmJoin()
    }

    func beginRecoveryKeyEntry() {
        controller?.beginRecoveryKeyEntry()
    }

    func useRecoveryKey(_ text: String) async {
        await controller?.useRecoveryKey(text)
    }

    func askAnotherDevice() {
        controller?.askAnotherMac()
    }

    func cancelFlow() {
        controller?.cancelFlow()
    }

    /// Looks for a request to approve and for the key another device sent; the Sync screen calls it while it is open.
    func refresh() {
        controller?.refresh()
    }

    func approve(_ pending: SyncPendingJoin) {
        controller?.allow(pending)
    }

    func deny(_ pending: SyncPendingJoin) {
        controller?.deny(pending)
    }

    // MARK: While it is on

    func syncNow() async {
        await controller?.syncNow()
    }

    func setIncludesSecrets(_ on: Bool) async {
        await controller?.setIncludesSecrets(on)
    }

    func turnOff() {
        controller?.pause()
    }

    /// Shows the recovery key after a fresh Face ID, Touch ID or passcode, as the Mac asks before it shows it.
    func showRecoveryKey() async {
        guard let controller, await HistoryLockPolicy.permitsSensitiveAction(
            using: env.authenticator, reason: String(localized: "Show the recovery key for Pesto sync"),
            requireFresh: true, grace: env.grace
        ) else { return }
        controller.presentRecoveryKey()
    }

    /// Whether Reset Sync or Leave Sync may go ahead: the same check as the Mac's protected actions.
    func permitsProtectedAction() async -> Bool {
        await HistoryLockPolicy.permitsProtectedAction(
            lockEnabled: env.defaults.value(for: Setting.biometricLockEnabled), using: env.authenticator,
            reason: String(localized: "Reset or leave Pesto sync"), grace: env.grace
        )
    }

    func reset() async {
        await controller?.reset()
    }

    func leave() {
        controller?.leave()
    }
}

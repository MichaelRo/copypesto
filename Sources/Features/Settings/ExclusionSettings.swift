// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Privacy → App Exclusions: one list of the apps Pesto never captures from. Apps you added can be removed.
/// Password managers and keychain tools are on it for good, but each can be allowed for a while
/// (`ExclusionAllowances`) behind Touch ID or the account password, for the day you need to keep something you copied
/// from one. What it keeps is hidden on the shelf, and removed when the allowance ends. Built-in apps that are not
/// installed on
/// this Mac stay excluded but are not listed, so the list shows only
/// apps you could recognise; one you install later is excluded from its first copy.
struct ExclusionSettings: View {
    @Environment(AppState.self) private var appState: AppState
    @AppStorage(Setting.additionalExcludedBundleIDs) private var additionalExcludedIDsRaw: String
    @State private var newBundleID = ""
    @State private var enteringBundleID = false
    @State private var allowances = ExclusionAllowances().active()
    @State private var message: String?

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let isBuiltIn: Bool
        let isInstalled: Bool
    }

    private var additionalIDs: [String] {
        ExclusionRules.userAdditions(from: additionalExcludedIDsRaw).sorted()
    }

    private var entries: [Entry] {
        let builtIn = ExclusionRules.defaultExcludedAppNames.compactMap { id, name -> Entry? in
            Self.isInstalled(id) ? Entry(id: id, name: name, isBuiltIn: true, isInstalled: true) : nil
        }
        let custom = additionalIDs.filter { !ExclusionRules.defaultExcludedBundleIDs.contains($0) }.map { id in
            Entry(id: id, name: Self.appName(for: id), isBuiltIn: false, isInstalled: Self.isInstalled(id))
        }
        return (builtIn + custom).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var hiddenBuiltInCount: Int {
        ExclusionRules.defaultExcludedBundleIDs.count { !Self.isInstalled($0) }
    }

    var body: some View {
        Section {
            Text("Pesto never captures a copy made in these apps.")
                .pestoCaption()
            ForEach(entries) { entry in
                HStack {
                    appLabel(entry)
                    Spacer()
                    if entry.isBuiltIn {
                        builtInControl(id: entry.id, name: entry.name)
                    } else {
                        if !entry.isInstalled {
                            Text("Not installed").pestoCaption()
                        }
                        Button("Remove") { removeID(entry.id) }
                            .accessibilityIdentifier(AccessibilityID.removeExcludedApp(entry.id))
                    }
                }
            }
            addMenu
            if let message { Text(message).pestoCaption() }
        } header: {
            Text("App exclusions").settingsRow("App exclusions")
        } footer: {
            Text(footer)
        }
        .alert("Add an app by bundle ID", isPresented: $enteringBundleID) {
            TextField("com.example.app", text: $newBundleID)
                .accessibilityIdentifier(AccessibilityID.excludedAppField)
            Button("Add") { addID(newBundleID) }
            Button("Cancel", role: .cancel) { newBundleID = "" }
        } message: {
            Text("For an app that is not installed on this Mac.")
        }
        .task { allowances = ExclusionAllowances().active() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            allowances = ExclusionAllowances().active()
        }
    }

    private var addMenu: some View {
        var items: [PopUpMenuItem] = [.action(String(localized: "Choose from Applications\u{2026}"), chooseApp)]
        if !runningApps.isEmpty {
            items.append(.divider)
            items.append(.header(String(localized: "Running now")))
            items += runningApps.map { app in .action(app.name) { addID(app.bundleID) } }
        }
        items.append(.divider)
        items.append(.action(String(localized: "Enter Bundle ID\u{2026}")) { enteringBundleID = true })
        return PopUpMenuButton(items: items) {
            HStack(spacing: 4) {
                Text("Add App\u{2026}")
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(AccessibilityID.addExcludedAppButton)
    }

    private var footer: String {
        var text = "Password managers hold your secrets, so they stay on this list. Allowing one keeps what you copy " +
            "from it for the time you choose, then it is excluded again, and it is excluded again when Pesto " +
            "quits. What is kept is hidden on the shelf, needs Touch ID or your password to open, and goes when " +
            "the allowance ends."
        if hiddenBuiltInCount > 0 {
            text +=
                " \(hiddenBuiltInCount) more password managers that are not on this Mac are excluded too, in case " +
                "you install them."
        }
        return text
    }

    /// A UI-test run has no password managers installed, so it lists every built-in app to stay the same on any Mac.
    private static func isInstalled(_ bundleID: String) -> Bool {
        if RuntimeConfiguration.current.mode != .normal, ExclusionRules.defaultExcludedBundleIDs.contains(bundleID) {
            return true
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    @ViewBuilder
    private func builtInControl(id: String, name: String) -> some View {
        let app = (id: id, name: name)
        if let end = allowances[app.id] {
            Text("Allowed \(Self.endText(end))")
                .pestoCaption()
            Button("Stop") {
                ExclusionAllowances().revoke(app.id)
                allowances = ExclusionAllowances().active()
            }
            .accessibilityIdentifier(AccessibilityID.revokeExclusionAllowance(app.id))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill").accessibilityHidden(true)
                Text("Excluded")
            }
            .pestoCaption()
            PopUpMenuButton(items: ExclusionAllowances.Length.allCases.map { length in
                .action(length.title) { Task { await allow(app, for: length) } }
            }) {
                HStack(spacing: 4) {
                    Text("Allow\u{2026}")
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).accessibilityHidden(true)
                }
            }
            .buttonStyle(.bordered)
            .disabled(appState.authenticationAvailability == .unavailable)
            .help(appState.authenticationAvailability.explanation ?? "")
            .accessibilityIdentifier(AccessibilityID.allowExclusion(app.id))
        }
    }

    private func appLabel(_ entry: Entry) -> some View {
        HStack(spacing: 8) {
            SourceAppIconView(bundleID: entry.id, appName: entry.name, size: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name)
                if entry.name != entry.id {
                    Text(entry.id).font(.caption2).pestoQuiet()
                }
            }
        }
    }

    private func allow(_ app: (id: String, name: String), for length: ExclusionAllowances.Length) async {
        guard await HistoryLockPolicy.permitsSensitiveAction(
            using: UserAuthenticator.current,
            reason: "Allow \(app.name) to be captured \(length.title.lowercased())"
        ) else {
            message = "\(app.name) stays excluded."
            return
        }
        ExclusionAllowances().allow(app.id, length: length)
        allowances = ExclusionAllowances().active()
        message = nil
    }

    private static func endText(_ end: Date) -> String {
        end == .distantFuture ? "until Pesto quits" : "until \(end.formatted(date: .omitted, time: .shortened))"
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowsMultipleSelection = false
        panel.message = "Choose an app Pesto should never capture from"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            message = "That app has no bundle identifier, so it cannot be excluded."
            return
        }
        addID(bundleID)
    }

    private var runningApps: [(bundleID: String, name: String)] {
        let excluded = Set(additionalIDs).union(ExclusionRules.defaultExcludedBundleIDs)
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier, !excluded.contains(id) else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private func addID(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        var ids = additionalIDs
        guard !trimmed.isEmpty, !ids.contains(trimmed) else { return }
        ids.append(trimmed)
        additionalExcludedIDsRaw = ids.joined(separator: ", ")
        newBundleID = ""
    }

    private func removeID(_ bundleID: String) {
        additionalExcludedIDsRaw = additionalIDs.filter { $0 != bundleID }.joined(separator: ", ")
    }

    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}

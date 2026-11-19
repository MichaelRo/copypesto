// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI

/// Settings sections about what Pesto captures and how it protects it: access, rules, the lock, the content filter.
struct CaptureSettings: View {
    enum Part {
        case accessibility, rules, sensitiveContent, lock
    }

    let part: Part
    @Environment(\.modelContext) private var modelContext
    @State private var nsfwRescanResult: String?

    // Automatic rules
    @AppStorage(Setting.ruleStripTracking) private var ruleStripTracking: Bool
    @AppStorage(Setting.ruleTrimWhitespace) private var ruleTrimWhitespace: Bool
    @AppStorage(Setting.ruleNormalizeLineEndings) private var ruleNormalizeLineEndings: Bool
    @AppStorage(Setting.ruleRemoveDuplicateSpaces) private var ruleRemoveDuplicateSpaces: Bool

    /// Biometric lock
    @AppStorage(Setting.biometricLockEnabled) private var biometricLockEnabled: Bool

    /// Content filtering
    @AppStorage(Setting.nsfwMode) private var nsfwModeRaw: String

    /// Refreshed each time the view appears so the badge reflects live state.
    @State private var isAXTrusted = AccessibilityAccess.isTrusted
    @Environment(AppState.self) private var appState: AppState
    private let lockMethod = LockMethod.current()
    @State private var captureAccess = PasteboardCaptureAccess.current()

    private var nsfwMode: NSFWMode {
        NSFWMode(rawValue: nsfwModeRaw) ?? .blur
    }

    var body: some View {
        Group {
            switch part {
            case .accessibility: accessibilitySection
            case .rules: rulesSection
            case .sensitiveContent: sensitiveContentSection
            case .lock: lockSection
            }
        }
        .onAppear {
            isAXTrusted = AccessibilityAccess.isTrusted
            captureAccess = PasteboardCaptureAccess.current()
        }
        // Granting a permission takes longer than any fixed wait: come back to Pesto and the row is current.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAXTrusted = AccessibilityAccess.isTrusted
            captureAccess = PasteboardCaptureAccess.current()
        }
    }

    // MARK: - Sections

    private var accessibilitySection: some View {
        Section {
            LabeledContent("Accessibility (auto-paste)") {
                HStack(spacing: 8) {
                    Label(
                        isAXTrusted ? "Granted" : "Not granted",
                        systemImage: isAXTrusted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(isAXTrusted ? Color.statusGood : Color.statusBad)
                    if !isAXTrusted {
                        Button("Open Settings\u{2026}") {
                            AccessibilityPermission.openSystemSettings()
                            // Re-check after a short delay in case the user grants it immediately.
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                isAXTrusted = AccessibilityAccess.isTrusted
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .settingsRow("Accessibility access")
            if captureAccess.needsAttention {
                LabeledContent {
                    Button("Open Pasteboard Settings\u{2026}") { PasteboardAccessSettings.open() }
                        .controlSize(.small)
                } label: {
                    Label(
                        captureAccess == .blocked ? "Clipboard capture is blocked" :
                            "macOS asks before Pesto reads the clipboard",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(Color.statusWarning)
                    .help(
                        "Allow \u{201C}Paste from Other Apps\u{201D} for Pesto in System Settings, " +
                            "under Privacy & Security, or history stops filling."
                    )
                }
                .settingsRow("Paste access (clipboard permission)")
            }
        } header: {
            Text("Permissions")
        } footer: {
            if !isAXTrusted {
                Text(
                    "Without Accessibility access, Pesto puts the clip on the clipboard and you press " +
                        "\u{2318}V to paste it."
                )
                .pestoCaption()
            } else {
                Text("Accessibility lets Pesto paste directly when you pick a clip.")
                    .pestoCaption()
            }
        }
    }

    private var rulesSection: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow {
                    Toggle("Strip URL tracking parameters", isOn: $ruleStripTracking)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsRow("Strip URL tracking parameters")
                    Toggle("Trim spaces at the start and end", isOn: $ruleTrimWhitespace)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsRow("Trim whitespace")
                }
                GridRow {
                    Toggle("Use one kind of line break", isOn: $ruleNormalizeLineEndings)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsRow("Normalize line endings")
                    Toggle("Collapse duplicate spaces", isOn: $ruleRemoveDuplicateSpaces)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsRow("Collapse duplicate spaces")
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Clean up copied text")
        } footer: {
            Text("Applied silently to every copied text clip before it is stored.").pestoCaption()
        }
    }

    private var lockSection: some View {
        Section {
            Toggle(lockMethod.settingsToggleTitle, isOn: Binding(
                get: { biometricLockEnabled },
                set: { wantsOn in
                    guard !wantsOn, biometricLockEnabled else {
                        let authenticator = UserAuthenticator.current
                        guard !wantsOn || HistoryLockPolicy.canSwitchOn(using: authenticator) else { return }
                        biometricLockEnabled = wantsOn
                        if wantsOn { HistoryLockPolicy.lockWasSwitchedOn() }
                        return
                    }
                    Task {
                        // Switching the lock off is the one change that must not need only a click.
                        if await HistoryLockPolicy.permitsTurningLockOff(
                            using: UserAuthenticator.current, reason: "Turn off the history lock"
                        ) {
                            biometricLockEnabled = false
                        }
                    }
                }
            ))
            .disabled(appState.authenticationAvailability == .unavailable && !biometricLockEnabled)
            .accessibilityIdentifier(AccessibilityID.settingsChoice("historyLock", "toggle"))
            .settingsRow("History lock (Touch ID)")
            if let explanation = appState.authenticationAvailability.explanation {
                Text(explanation).pestoCaption()
                    .accessibilityIdentifier(AccessibilityID.authenticationUnavailable)
            }
            AuthenticationGracePicker()
                .settingsRow("Ask for Touch ID again after")
        } header: {
            Text("History lock")
        } footer: {
            HStack(spacing: 6) {
                Text("When locked, your history is blurred until you authenticate with \(lockMethod.name).")
                    .pestoCaption()
                InfoPopoverButton(
                    "How the timer works",
                    message: "After you confirm, Pesto does not ask again for this long. With the lock on it is " +
                        "also how long your history stays open; showing a hidden clip and, with the lock on, " +
                        "backups and exports use it too. Clearing everything and showing the recovery key always " +
                        "ask. Locking the screen or the history ends it."
                )
            }
        }
    }

    private var nsfwModeBinding: Binding<NSFWMode> {
        Binding(get: { nsfwMode }, set: { nsfwModeRaw = $0.rawValue })
    }

    private var sensitiveContentSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                Text("Explicit pictures and links")
                Spacer()
                PreviewPicker(
                    title: "Explicit pictures and links", options: NSFWMode.allCases, selection: nsfwModeBinding,
                    label: \.title,
                    identifier: { AccessibilityID.settingsChoice("nsfwMode", $0.rawValue) },
                    tileSize: CGSize(width: 72, height: 44),
                    cornerRadius: 8,
                    preview: { FilterModePreview(mode: $0) }
                )
                .fixedSize()
            }
            .settingsRow("Sensitive content filter")
            .onChange(of: nsfwModeRaw) {
                if NSFWMode(rawValue: nsfwModeRaw)?.detectsContent == true { rescanNSFW() }
            }
            if let result = nsfwRescanResult {
                Text(result).pestoCaption()
            }
        } header: {
            Text("Sensitive content")
        } footer: {
            HStack(spacing: 6) {
                Text(
                    AppleIntelligenceClient.supportsVision
                        ? "Secrets and explicit content are screened on this Mac."
                        : "Secrets are masked on this Mac; picture screening needs Apple Intelligence."
                )
                .pestoCaption()
                InfoPopoverButton(
                    "About sensitive content",
                    verbatimMessage: ContentFilterNotice.text(
                        pictureScreeningAvailable: AppleIntelligenceClient.supportsVision
                    )
                )
            }
        }
    }

    private func rescanNSFW() {
        let container = modelContext.container
        let mode = nsfwMode
        nsfwRescanResult = String(localized: "Scanning existing clips…")
        Task {
            do {
                let service = StorageService(modelContainer: container)
                let flagged = try await service.rescanNSFWImages()
                await MainActor.run {
                    nsfwRescanResult = switch (flagged, mode) {
                    case (0, _): String(localized: "No sensitive clips found.")
                    case (_, .hide): String(localized: "Hid \(flagged) sensitive clips.")
                    default: String(localized: "Blurred \(flagged) sensitive clips.")
                    }
                }
            } catch {
                await MainActor.run { nsfwRescanResult = String(localized: "The scan failed. Try again.") }
            }
        }
    }

    /// What Privacy tells about encryption at rest; it must say that some details stay readable (a test checks).
    static let encryptionCaption =
        "What you copy, its preview, and your titles, notes and tags are encrypted with AES-256-GCM before " +
        "they are written to disk. The key is kept in this Mac\u{2019}s Keychain and is never sent " +
        "anywhere. A few details stay readable, such as the app a clip came from, when it was copied, " +
        "collection names and the masked preview of a secret; the guide lists them all."
}

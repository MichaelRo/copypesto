// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// About Pesto: the icon on the brand backdrop, the name, the version, the site's one line, three links and the
/// copyright. The backdrop sits behind the picture only, never behind text.
struct AboutView: View {
    static let windowSize = CGSize(width: 380, height: 548)

    @Environment(\.shelfActions) private var shelfActions: ShelfActionDispatcher
    @AppStorage(Setting.appIcon) private var appIconRaw: String

    private var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    private var versionLine: String {
        AppVersion.displayString(info: info)
    }

    private var copyright: String {
        info["NSHumanReadableCopyright"] as? String ?? ""
    }

    private static let links: [(title: LocalizedStringKey, url: URL?)] = [
        ("Website", URL(string: "https://copypesto.net/")),
        ("Release Notes", URL(string: "https://copypesto.net/releases/")),
        ("Privacy", URL(string: "https://copypesto.net/privacy/"))
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                BrandBackdropView()
                Image(AppIconChoice(stored: appIconRaw).previewImageName)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                    .settleOnAppear(.hop)
                    .accessibilityHidden(true)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text("Pesto").font(.largeTitle.bold())
                Text(versionLine)
                    .font(.callout)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .textSelection(.enabled)
                Text("Everything you copy. Readable only by you.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)

            HStack(spacing: 8) {
                ForEach(Array(Self.links.enumerated()), id: \.offset) { _, link in
                    if let url = link.url { Link(destination: url) { Text(link.title) } }
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 20)

            if let check = shelfActions.checkForUpdates {
                Button("Check for Updates\u{2026}", action: check)
                    .buttonStyle(.bordered)
                    .padding(.top, 12)
            }

            HStack(spacing: 14) {
                if let notices = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md") {
                    Button("Acknowledgments") { NSWorkspace.shared.open(notices) }
                }
                Button("Copy Diagnostics") {
                    shelfActions.writeText(DiagnosticsReport.text(DiagnosticsFacts.current()), false)
                    Announcer.announce(String(localized: "Diagnostics copied."))
                }
                .help("Copies Pesto and macOS versions and which switches are on, for a bug report. No clips.")
                .accessibilityIdentifier(AccessibilityID.copyDiagnosticsButton)
            }
            .buttonStyle(.pestoLink)
            .padding(.top, 8)

            if let showWelcome = shelfActions.showWelcome {
                Button("Show Welcome Screen", action: showWelcome)
                    .buttonStyle(.pestoLink)
                    .padding(.top, 8)
                    .accessibilityIdentifier(AccessibilityID.showWelcomeButton)
            }

            Spacer(minLength: 12)

            Text(copyright)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

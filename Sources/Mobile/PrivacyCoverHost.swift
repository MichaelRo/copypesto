// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

/// The App Switcher keeps a picture of the app as it left (ADR 0054): while the scene is not active, a window of
/// its own above every sheet and alert covers it with a plain ground, so no card, detail or editor is in that
/// picture.
struct PrivacyCoverHost: UIViewRepresentable {
    let covers: Bool

    static func covers(in phase: ScenePhase) -> Bool {
        phase != .active
    }

    func makeUIView(context _: Context) -> PrivacyCoverAnchor {
        PrivacyCoverAnchor()
    }

    func updateUIView(_ view: PrivacyCoverAnchor, context _: Context) {
        view.setCovering(covers)
    }
}

final class PrivacyCoverAnchor: UIView {
    private var cover: UIWindow?
    private var covers = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        apply()
    }

    func setCovering(_ covering: Bool) {
        covers = covering
        apply()
    }

    private func apply() {
        guard covers else {
            cover?.isHidden = true
            return
        }
        guard let scene = window?.windowScene else { return }
        let shown = cover ?? Self.makeCover(in: scene)
        cover = shown
        shown.isHidden = false
    }

    private static func makeCover(in scene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: PrivacyCoverView())
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host
        return window
    }
}

struct PrivacyCoverView: View {
    var body: some View {
        Image(systemName: "eye.slash")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .accessibilityIdentifier(MobileAccessibilityID.privacyCover)
            .accessibilityLabel(Text("Pesto"))
    }
}

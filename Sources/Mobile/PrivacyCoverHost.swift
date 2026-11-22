// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

/// The App Switcher keeps a picture of the app as it left (ADR 0054): when the scene enters the background while
/// unlocked, a window above sheets covers it calmly so no card, detail or editor appears in the snapshot, while
/// `.inactive` system prompts such as Face ID are never obscured.
struct PrivacyCoverHost: UIViewRepresentable {
    let covers: Bool

    static func covers(in phase: ScenePhase, isLocked: Bool = false) -> Bool {
        phase == .background && !isLocked
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
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text("Pesto")
                    .font(.headline)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(MobileAccessibilityID.privacyCover)
        .accessibilityLabel(Text("Pesto"))
    }
}

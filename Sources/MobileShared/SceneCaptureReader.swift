// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

/// Whether iOS is recording, mirroring or AirPlaying this scene: the scene's `sceneCaptureState` trait (iOS 17; the
/// older `UIScreen.isCaptured` is deprecated), read when the view joins a window and on every change of that trait.
struct SceneCaptureReader: UIViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeUIView(context _: Context) -> CaptureStateView {
        CaptureStateView(onChange: onChange)
    }

    func updateUIView(_ view: CaptureStateView, context _: Context) {
        view.onChange = onChange
    }
}

final class CaptureStateView: UIView {
    var onChange: @MainActor (Bool) -> Void
    private var reported: Bool?

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        registerForTraitChanges([UITraitSceneCaptureState.self]) { (view: CaptureStateView, _) in
            view.report()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    private func report() {
        guard window != nil else { return }
        let captured = traitCollection.sceneCaptureState == .active
        guard captured != reported else { return }
        reported = captured
        onChange(captured)
    }
}

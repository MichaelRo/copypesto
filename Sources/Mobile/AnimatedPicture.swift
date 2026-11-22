// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

/// A GIF's frames played by UIKit (SwiftUI's `Image` shows only the first frame). It fills or fits its space, as the
/// still picture beside it would.
struct AnimatedPicture: UIViewRepresentable {
    let animation: GIFFrames.Animation
    let fills: Bool

    func makeUIView(context _: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIImageView, context _: Context) {
        view.contentMode = fills ? .scaleAspectFill : .scaleAspectFit
        let changed = view.animationImages?.first !== animation.frames.first
            || view.animationImages?.count != animation.frames.count
            || view.animationDuration != animation.duration
        guard changed else { return }
        view.image = animation.frames.first
        view.animationImages = animation.frames
        view.animationDuration = animation.duration
        view.startAnimating()
    }

    static func dismantleUIView(_ view: UIImageView, coordinator _: ()) {
        view.stopAnimating()
        view.animationImages = nil
    }
}

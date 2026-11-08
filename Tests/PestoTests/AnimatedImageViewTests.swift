// SPDX-License-Identifier: MIT
import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import Pesto

@Suite("Animated image view and popover rendering")
@MainActor
struct AnimatedImageViewTests {
    @Test("when an animated image is wide, sizeThatFits preserves its aspect ratio within bounds")
    func whenWideImage_thenSizeThatFitsPreservesAspect() {
        let imageSize = CGSize(width: 480, height: 240) // 2:1 aspect ratio
        let proposal = ProposedViewSize(width: 288, height: 180)
        let size = AnimatedImageView.sizeThatFits(imageSize: imageSize, proposal: proposal)

        #expect(size != nil)
        if let size {
            #expect(size.width == 288)
            #expect(size.height == 144) // 288 / 2 = 144, not forced 180 or forced minHeight
        }
    }

    @Test("when an animated image is tall, sizeThatFits preserves its aspect ratio within bounds")
    func whenTallImage_thenSizeThatFitsPreservesAspect() {
        let imageSize = CGSize(width: 200, height: 400) // 1:2 aspect ratio
        let proposal = ProposedViewSize(width: 288, height: 180)
        let size = AnimatedImageView.sizeThatFits(imageSize: imageSize, proposal: proposal)

        #expect(size != nil)
        if let size {
            #expect(size.width == 90) // 180 * 0.5 = 90, not forced 288
            #expect(size.height == 180)
        }
    }

    @Test("when SynchronizedGIFImageView is created and configured, its contentsGravity is resizeAspect")
    func whenConfigured_thenContentsGravityIsResizeAspect() {
        let image = NSImage(size: NSSize(width: 320, height: 240))
        let imageView = SynchronizedGIFImageView()
        imageView.wantsLayer = true
        imageView.configure(image: image, animates: false, scaling: .scaleProportionallyUpOrDown)

        #expect(imageView.layer?.contentsGravity == .resizeAspect)
    }

    @Test("when hosting AnimatedImageView in a constrained frame, fitting size respects aspect fit")
    func whenHostedInSwiftUI_thenFittingSizeRespectsAspectFit() {
        let image = NSImage(size: NSSize(width: 480, height: 240))
        let aspect = image.size.width / image.size.height

        struct ContainerView: View {
            let img: NSImage
            let asp: CGFloat
            var body: some View {
                VStack {
                    AnimatedImageView(image: img, animates: false)
                        .aspectRatio(asp, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 180)
                }
                .frame(width: 288)
            }
        }

        let host = NSHostingController(rootView: ContainerView(img: image, asp: aspect))
        let fitting = host.view.fittingSize
        #expect(fitting.width == 288)
        #expect(fitting.height == 144)
    }

    @Test("when proposal has infinite dimensions, sizeThatFits falls back gracefully")
    func whenInfiniteProposal_thenFallsBackGracefully() {
        let imageSize = CGSize(width: 300, height: 150)
        let infiniteProposal = ProposedViewSize(width: .infinity, height: .infinity)
        let size = AnimatedImageView.sizeThatFits(imageSize: imageSize, proposal: infiniteProposal)
        #expect(size != nil)
        if let size {
            #expect(size.width.isFinite)
            #expect(size.height.isFinite)
            #expect(size.width == 300)
            #expect(size.height == 150)
        }
    }
}

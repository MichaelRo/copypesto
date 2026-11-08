// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import QuartzCore
import SwiftUI

/// Wraps `NSImageView` so multi-frame GIFs can play in lockstep across the shelf card and the hover card.
/// `Image(nsImage:)` only renders the first frame; this view steps frames against a shared monotonic clock when
/// `animates` is true and holds the first frame otherwise.
struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage
    var animates = true
    var contentMode: NSImageScaling = .scaleProportionallyUpOrDown
    var aspectFit = false

    static func sizeThatFits(imageSize: CGSize, proposal: ProposedViewSize) -> CGSize? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let aspect = imageSize.width / imageSize.height
        let targetWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? imageSize.width
        let targetHeight = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? (targetWidth / aspect)
        let scaledHeight = min(targetHeight, targetWidth / aspect)
        let scaledWidth = min(targetWidth, scaledHeight * aspect)
        return CGSize(width: scaledWidth, height: scaledHeight)
    }

    func makeNSView(context _: Context) -> SynchronizedGIFImageView {
        let view = SynchronizedGIFImageView()
        view.imageAlignment = .alignCenter
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.configure(image: image, animates: animates, scaling: contentMode, aspectFit: aspectFit)
        return view
    }

    func updateNSView(_ nsView: SynchronizedGIFImageView, context _: Context) {
        nsView.configure(image: image, animates: animates, scaling: contentMode, aspectFit: aspectFit)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: SynchronizedGIFImageView, context _: Context) -> CGSize? {
        guard aspectFit else { return nil }
        return Self.sizeThatFits(imageSize: image.size, proposal: proposal)
    }
}

@MainActor
final class SynchronizedGIFImageView: NSImageView {
    private(set) var shouldAnimate = false
    var lastRenderedFrameIndex: Int?

    func configure(image: NSImage, animates: Bool, scaling: NSImageScaling, aspectFit: Bool = false) {
        let changedImage = self.image !== image
        if changedImage {
            self.image = image
            lastRenderedFrameIndex = nil
        }
        imageScaling = scaling
        if aspectFit {
            layer?.contentsGravity = .resizeAspect
        }
        super.animates = false
        shouldAnimate = animates
        AnimatedGIFClock.shared.updateMembership(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        AnimatedGIFClock.shared.updateMembership(for: self)
    }
}

@MainActor
private final class AnimatedGIFClock {
    static let shared = AnimatedGIFClock()

    private let activeViews = NSHashTable<SynchronizedGIFImageView>.weakObjects()
    private var durationsByRep: [ObjectIdentifier: [TimeInterval]] = [:]
    private var timer: Timer?

    func updateMembership(for view: SynchronizedGIFImageView) {
        guard let rep = bitmapRep(in: view.image), frameCount(of: rep) > 1 else {
            activeViews.remove(view)
            stopTimerIfIdle()
            return
        }
        if view.window != nil, view.shouldAnimate {
            activeViews.add(view)
            syncFrame(for: view, rep: rep, uptime: ProcessInfo.processInfo.systemUptime)
            startTimerIfNeeded()
        } else {
            activeViews.remove(view)
            if !view.shouldAnimate {
                setFrame(0, on: rep, for: view)
            }
            stopTimerIfIdle()
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let newTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimerIfIdle() {
        if activeViews.allObjects.isEmpty {
            timer?.invalidate()
            timer = nil
            durationsByRep.removeAll(keepingCapacity: true)
        }
    }

    private func tick() {
        let views = activeViews.allObjects.filter { $0.window != nil && $0.shouldAnimate }
        if views.isEmpty {
            stopTimerIfIdle()
            return
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        for view in views {
            guard let rep = bitmapRep(in: view.image) else { continue }
            syncFrame(for: view, rep: rep, uptime: uptime)
        }
    }

    private func syncFrame(for view: SynchronizedGIFImageView, rep: NSBitmapImageRep, uptime: TimeInterval) {
        let durations = frameDurations(for: rep)
        let target = AnimatedImagePlayback.frameIndex(at: uptime, durations: durations)
        setFrame(target, on: rep, for: view)
    }

    private func setFrame(_ index: Int, on rep: NSBitmapImageRep, for view: SynchronizedGIFImageView) {
        guard view.lastRenderedFrameIndex != index else { return }
        let current = rep.value(forProperty: .currentFrame) as? Int
        if current != index {
            rep.setProperty(.currentFrame, withValue: index)
        }
        view.lastRenderedFrameIndex = index
        view.needsDisplay = true
    }

    private func bitmapRep(in image: NSImage?) -> NSBitmapImageRep? {
        image?.representations.compactMap { $0 as? NSBitmapImageRep }.first
    }

    private func frameCount(of rep: NSBitmapImageRep) -> Int {
        rep.value(forProperty: .frameCount) as? Int ?? 1
    }

    private func frameDurations(for rep: NSBitmapImageRep) -> [TimeInterval] {
        let key = ObjectIdentifier(rep)
        if let cached = durationsByRep[key] { return cached }
        let count = frameCount(of: rep)
        let saved = rep.value(forProperty: .currentFrame) as? Int ?? 0
        var durations: [TimeInterval] = []
        durations.reserveCapacity(count)
        for index in 0..<count {
            rep.setProperty(.currentFrame, withValue: index)
            let raw = (rep.value(forProperty: .currentFrameDuration) as? NSNumber)?.doubleValue ?? 0.10
            durations.append(AnimatedImagePlayback.normalizedDuration(raw))
        }
        rep.setProperty(.currentFrame, withValue: saved)
        durationsByRep[key] = durations
        return durations
    }
}

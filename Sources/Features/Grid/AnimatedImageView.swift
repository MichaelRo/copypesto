// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// Wraps `NSImageView` so multi-frame GIFs can play in lockstep across the shelf card and the hover card.
/// `Image(nsImage:)` only renders the first frame; this view steps frames against a shared monotonic clock when
/// `animates` is true and holds the first frame otherwise.
struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage
    var animates = true
    var contentMode: NSImageScaling = .scaleProportionallyUpOrDown

    func makeNSView(context _: Context) -> SynchronizedGIFImageView {
        let view = SynchronizedGIFImageView()
        view.imageAlignment = .alignCenter
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.configure(image: image, animates: animates, scaling: contentMode)
        return view
    }

    func updateNSView(_ nsView: SynchronizedGIFImageView, context _: Context) {
        nsView.configure(image: image, animates: animates, scaling: contentMode)
    }
}

@MainActor
final class SynchronizedGIFImageView: NSImageView {
    private(set) var shouldAnimate = false

    func configure(image: NSImage, animates: Bool, scaling: NSImageScaling) {
        let changedImage = self.image !== image
        if changedImage {
            self.image = image
        }
        imageScaling = scaling
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
        let current = rep.value(forProperty: .currentFrame) as? Int
        if current != index {
            rep.setProperty(.currentFrame, withValue: index)
        }
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

// SPDX-License-Identifier: MIT
// Attaches a ScreenCaptureKit SCStream (up to 120 Hz) to Pesto's OverlayPanel while cycling collections (⌘] / ⌘[)
// on a 5,000-clip history, failing if any intermediate frame is blank or shows a stale collection mismatch.
//
// Usage: check-collection-switch-flash <work-dir> [cycles]
import AppKit
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

private func logOut(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

private final class FrameAnalyzer: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var totalFrames = 0
    private(set) var blankFrames = 0
    private(set) var staleFrames = 0
    private(set) var firstBlankDetail: String?
    private(set) var firstStaleDetail: String?

    private var prevChipHash: UInt64?
    private var prevGridHash: UInt64?
    private var pendingChipChangeFrames = 0

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 40, height > 40, let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        let gridMetrics = sampleGrid(ptr: ptr, width: width, height: height, bytesPerRow: bytesPerRow)
        guard gridMetrics.count > 0.5 else { return }
        let chipHash = sampleChipBar(ptr: ptr, width: width, height: height, bytesPerRow: bytesPerRow)

        let mean = gridMetrics.sum / gridMetrics.count
        let variance = (gridMetrics.sumSq / gridMetrics.count) - (mean * mean)

        recordFrame(
            variance: variance,
            nonZeroAlpha: gridMetrics.nonZeroAlpha,
            chipHash: chipHash,
            gridHash: gridMetrics.hash
        )
    }

    private struct GridMetrics {
        let sum: Double
        let sumSq: Double
        let count: Double
        let nonZeroAlpha: Int
        let hash: UInt64
    }

    private func sampleGrid(
        ptr: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int
    )
    -> GridMetrics {
        let gridTop = height * 35 / 100
        let gridBottom = height * 90 / 100
        let xStart = width / 10
        let xEnd = width * 9 / 10
        let stepX = max(4, (xEnd - xStart) / 32)
        let stepY = max(4, (gridBottom - gridTop) / 16)

        var sum = 0.0
        var sumSq = 0.0
        var count = 0.0
        var nonZeroAlpha = 0
        var gridHash: UInt64 = 14_695_981_039_346_656_037

        var y = gridTop
        while y < gridBottom {
            let row = ptr + y * bytesPerRow
            var x = xStart
            while x < xEnd {
                let luma = 0.2126 * Double(row[x * 4 + 2])
                    + 0.7152 * Double(row[x * 4 + 1])
                    + 0.0722 * Double(row[x * 4])
                if row[x * 4 + 3] > 8 { nonZeroAlpha += 1 }
                sum += luma
                sumSq += luma * luma
                count += 1
                gridHash = (gridHash ^ UInt64(luma / 8.0)) &* 1_099_511_628_211
                x += stepX
            }
            y += stepY
        }
        return GridMetrics(sum: sum, sumSq: sumSq, count: count, nonZeroAlpha: nonZeroAlpha, hash: gridHash)
    }

    private func sampleChipBar(ptr: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> UInt64 {
        let xStart = width / 10
        let xEnd = width * 9 / 10
        let stepX = max(4, (xEnd - xStart) / 32)
        let stepY = max(2, max(4, (height * 55 / 100) / 16) / 2)
        let chipTop = max(4, height * 4 / 100)
        let chipBottom = max(chipTop + 8, height * 18 / 100)
        var chipHash: UInt64 = 14_695_981_039_346_656_037
        var y = chipTop
        while y < chipBottom {
            let row = ptr + y * bytesPerRow
            var x = xStart
            while x < xEnd {
                let luma = UInt64((Int(row[x * 4 + 2]) + Int(row[x * 4 + 1]) + Int(row[x * 4])) / 24)
                chipHash = (chipHash ^ luma) &* 1_099_511_628_211
                x += stepX
            }
            y += stepY
        }
        return chipHash
    }

    private func recordFrame(variance: Double, nonZeroAlpha: Int, chipHash: UInt64, gridHash: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        totalFrames += 1

        if nonZeroAlpha == 0 || variance < 1.5 {
            blankFrames += 1
            if firstBlankDetail == nil {
                let varStr = String(format: "%.2f", variance)
                firstBlankDetail = "frame=\(totalFrames) variance=\(varStr) nonZeroAlpha=\(nonZeroAlpha)"
            }
            return
        }

        if let pChip = prevChipHash, let pGrid = prevGridHash {
            if chipHash != pChip, gridHash == pGrid {
                pendingChipChangeFrames += 1
                if pendingChipChangeFrames > 2 {
                    staleFrames += 1
                    if firstStaleDetail == nil {
                        firstStaleDetail = "frame=\(totalFrames) pending=\(pendingChipChangeFrames)"
                    }
                }
            } else {
                pendingChipChangeFrames = 0
            }
        }
        prevChipHash = chipHash
        prevGridHash = gridHash
    }
}

private func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
    let src = CGEventSource(stateID: .hidSystemState)
    guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else { return }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

@main
struct CollectionSwitchFlashCheck {
    static func main() async {
        await MainActor.run {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
        }
        let args = CommandLine.arguments
        let cycles = args.count > 2 ? (Int(args[2]) ?? 12) : 12

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let overlay = content.windows.first(where: {
                let app = $0.owningApplication
                let isPesto = app?.applicationName == "Pesto" || app?.bundleIdentifier == "net.copypesto.pesto"
                return isPesto && $0.frame.width > 300 && $0.frame.height > 120
            }) else {
                fputs("error: OverlayPanel window not found in SCShareableContent\n", stderr)
                exit(1)
            }

            let filter = SCContentFilter(desktopIndependentWindow: overlay)
            let config = SCStreamConfiguration()
            config.width = Int(overlay.frame.width) * 2
            config.height = Int(overlay.frame.height) * 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
            config.queueDepth = 8
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let analyzer = FrameAnalyzer()
            let queue = DispatchQueue(label: "net.copypesto.flash-check", qos: .userInteractive)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(analyzer, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            try await Task.sleep(nanoseconds: 350_000_000)

            for _ in 0..<cycles {
                postKey(keyCode: 30, flags: .maskCommand)
                try await Task.sleep(nanoseconds: 180_000_000)
                postKey(keyCode: 33, flags: .maskCommand)
                try await Task.sleep(nanoseconds: 180_000_000)
            }

            try await Task.sleep(nanoseconds: 300_000_000)
            try await stream.stopCapture()

            logOut("frames=\(analyzer.totalFrames) blank=\(analyzer.blankFrames) stale=\(analyzer.staleFrames)")
            if analyzer.totalFrames < 10 {
                fputs("error: too few frames captured (\(analyzer.totalFrames))\n", stderr)
                exit(1)
            }
            if analyzer.blankFrames > 0 {
                fputs("FAIL: blank intermediate frame (\(analyzer.firstBlankDetail ?? ""))\n", stderr)
                exit(1)
            }
            if analyzer.staleFrames > 0 {
                fputs("FAIL: stale-collection frame (\(analyzer.firstStaleDetail ?? ""))\n", stderr)
                exit(1)
            }
            logOut("ok    no blank or stale-collection frames across \(cycles) ⌘]/⌘[ cycles")
        } catch {
            fputs("error: ScreenCaptureKit failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

// SPDX-License-Identifier: MIT
// Records only Pesto's own windows (the UI-test backdrop, the shelf, sheets) with ScreenCaptureKit, so the notice and
// dimming macOS draws during a UI test, and every other window on the Mac, stay out of the picture.
//   window-recorder <output.mov> [bundle id, default net.copypesto.pesto]
// Starts when the app's windows exist and stops on SIGINT or SIGTERM. Needs Screen Recording permission for the
// terminal.
import AVFoundation
import CoreMedia
import ScreenCaptureKit

final class Recorder: NSObject, SCStreamOutput {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false

    init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 40_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let info =
              (CMSampleBufferGetSampleAttachmentsArray(
                  buffer,
                  createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(buffer) }
    }

    func finish() async {
        guard started else { return }
        input.markAsFinished()
        await writer.finishWriting()
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fail("usage: window-recorder <output.mov> [bundle id]") }
let output = URL(fileURLWithPath: arguments[1])
let bundleID = arguments.count > 2 ? arguments[2] : "net.copypesto.pesto"

var signalSources: [DispatchSourceSignal] = []

Task {
    var app: SCRunningApplication?
    var display: SCDisplay?
    for _ in 0..<600 {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            fail("Screen capture is not allowed: grant Screen Recording to this terminal and restart it.")
        }
        display = content.displays.first
        app = content.applications.first { $0.bundleIdentifier == bundleID }
        if app != nil,
           content.windows
               .contains(where: { $0.owningApplication?.bundleIdentifier == bundleID && $0.frame.height > 600 })
        {
            break
        }
        app = nil
        try? await Task.sleep(for: .milliseconds(100))
    }
    guard let app, let display else { fail("\(bundleID) never showed a window") }

    // The backdrop sits below the menu bar; record that region at the display's pixel scale.
    let scale = 2
    let region = CGRect(x: 0, y: 33, width: display.width, height: display.height - 33)
    let configuration = SCStreamConfiguration()
    configuration.sourceRect = region
    configuration.width = Int(region.width) * scale
    configuration.height = Int(region.height) * scale
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = true
    configuration.queueDepth = 6

    let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
    let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
    guard let recorder = try? Recorder(url: output, width: configuration.width, height: configuration.height) else { fail("cannot write \(output.path)") }
    try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
    try await stream.startCapture()
    print("recording \(Int(region.width) * scale)x\(Int(region.height) * scale)")

    let stop = DispatchSemaphore(value: 0)
    for signalNumber in [SIGINT, SIGTERM] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler { stop.signal() }
        source.resume()
        signalSources.append(source)
    }
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            stop.wait()
            continuation.resume()
        }
    }
    try? await stream.stopCapture()
    await recorder.finish()
    exit(0)
}

RunLoop.main.run()

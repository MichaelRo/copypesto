// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PestoMobile

@Suite("A GIF plays on a card only when it may, and only in bounded memory")
struct GIFFramesTests {
    private func gif(frames: Int, side: Int, delay: Double) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.gif.identifier as CFString, frames, nil
        ))
        for index in 0..<frames {
            let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
                UIColor(hue: CGFloat(index) / CGFloat(frames), saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }
            let frame = try #require(image.cgImage)
            CGImageDestinationAddImage(
                destination, frame,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            )
        }
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("it plays when animated, on screen, not covered and Reduce Motion is off; otherwise the first frame stays")
    func whenDeciding_thenEveryConditionCounts() {
        #expect(CardAnimation.plays(isAnimated: true, isOnScreen: true, isConcealed: false, reduceMotion: false))
        #expect(!CardAnimation.plays(isAnimated: false, isOnScreen: true, isConcealed: false, reduceMotion: false))
        #expect(!CardAnimation.plays(isAnimated: true, isOnScreen: false, isConcealed: false, reduceMotion: false))
        #expect(!CardAnimation.plays(isAnimated: true, isOnScreen: true, isConcealed: true, reduceMotion: false))
        #expect(!CardAnimation.plays(isAnimated: true, isOnScreen: true, isConcealed: false, reduceMotion: true))
    }

    @Test("the plan keeps as many frames as the bytes allow, dropped evenly")
    func whenPlanned_thenTheBudgetHolds() {
        #expect(GIFFrames.plan(total: 60, frameBytes: 1000, maxBytes: 100_000) == (60, 1))
        let plan = GIFFrames.plan(total: 60, frameBytes: 1000, maxBytes: 10_000)
        #expect(plan.count * 1000 <= 10_000)
        #expect(plan.step == 6)
        #expect(GIFFrames.plan(total: 60, frameBytes: 1000, maxBytes: 10).count == 1)
    }

    @Test("decoded frames are scaled down, few enough for the budget, and keep the GIF's length")
    func whenDecoded_thenFramesAreBounded() async throws {
        let data = try gif(frames: 30, side: 400, delay: 0.1)
        let budget = GIFFrames.Budget(maxPixel: 100, maxBytes: 100 * 100 * 4 * 6)

        let animation = try #require(await GIFFrames.decode(data, budget: budget))

        #expect(animation.frames.count > 1)
        #expect(animation.frames.count <= 6)
        let bytes = animation.frames.reduce(0) { total, frame in
            total + (frame.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
        }
        #expect(bytes <= budget.maxBytes)
        #expect(animation.frames.allSatisfy { max($0.size.width, $0.size.height) <= 100 })
        #expect(abs(animation.duration - 3.0) < 0.05)
    }

    @Test("a still picture has no frames to play")
    func whenOneFrame_thenNothingPlays() async throws {
        #expect(try await GIFFrames.decode(gif(frames: 1, side: 50, delay: 0.1), budget: .card) == nil)
    }
}

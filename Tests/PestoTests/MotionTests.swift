// SPDX-License-Identifier: MIT
import SwiftUI
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Motion", .serialized)
    @MainActor
    struct MotionTests {
        @Test("with Reduce Motion on, no animation is returned")
        func whenReduceMotion_thenNil() {
            Motion.reduceMotionOverride = true
            defer { Motion.reduceMotionOverride = nil }

            #expect(Motion.animation(.easeInOut(duration: 0.2)) == nil)
        }

        @Test("with Reduce Motion off, the requested animation is returned")
        func whenMotionAllowed_thenAnimation() {
            Motion.reduceMotionOverride = false
            defer { Motion.reduceMotionOverride = nil }

            #expect(Motion.animation(.easeInOut(duration: 0.2)) != nil)
        }

        @Test("the picture settle moves only when Reduce Motion is off")
        func settleFollowsReduceMotion() {
            defer { Motion.reduceMotionOverride = nil }
            for style in [SettleOnAppear.Style.sway, .hop] {
                Motion.reduceMotionOverride = true
                #expect(Motion.animation(style.animation) == nil)
                Motion.reduceMotionOverride = false
                #expect(Motion.animation(style.animation) != nil)
            }
        }
    }
}

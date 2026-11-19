// SPDX-License-Identifier: MIT
import SwiftUI

/// The jar on its shelf with one cream card: when its step comes into view the card drops onto the shelf after a beat,
/// then the jar's leaf settles, once (ADR 0057). The layers come from `design/source/brand-art.py --mobile`. Under
/// Reduce Motion the final frame is drawn.
struct WelcomeKeepArt: View {
    let isActive: Bool
    @State private var landed = Motion.reduceMotion
    @State private var leafSettled = Motion.reduceMotion

    var body: some View {
        ZStack {
            Image("WelcomeShelf").resizable().scaledToFit()
            Image("WelcomeCard").resizable().scaledToFit().offset(y: landed ? 0 : -24)
            Image("WelcomeJar").resizable().scaledToFit()
            Image("WelcomeLeaf").resizable().scaledToFit()
                .scaleEffect(leafSettled ? 1 : 0.92, anchor: UnitPoint(x: 238 / 360, y: 172 / 240))
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .accessibilityHidden(true)
        .task(id: isActive) {
            guard isActive, !landed else { return }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(Motion.animation(.pestoMove)) { landed = true }
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(Motion.animation(.pestoPop)) { leafSettled = true }
        }
    }
}

/// Basil between a Mac card and a phone card: one card glides from the Mac to the phone, once.
struct WelcomeSyncArt: View {
    private static let glide: CGFloat = 198 / 360
    let isActive: Bool
    @State private var glided = Motion.reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("WelcomeShelf").resizable().scaledToFit()
                Image("SyncMac").resizable().scaledToFit()
                Image("SyncPhone").resizable().scaledToFit()
                Image("SyncCard").resizable().scaledToFit()
                    .offset(x: glided ? proxy.size.width * Self.glide : 0)
                Image("SyncBasil").resizable().scaledToFit()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .accessibilityHidden(true)
        .task(id: isActive) {
            guard isActive, !glided else { return }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(Motion.animation(.pestoWash)) { glided = true }
        }
    }
}

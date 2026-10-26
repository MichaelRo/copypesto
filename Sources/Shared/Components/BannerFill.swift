// SPDX-License-Identifier: MIT
import SwiftUI

public struct BannerFill: View {
    public let tint: Color
    @Environment(\.colorSchemeContrast) private var contrast

    public init(tint: Color) {
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Color.opaqueSurface
            tint.opacity(0.10)
            if contrast == .increased {
                Rectangle().strokeBorder(tint.opacity(0.6), lineWidth: 1)
            }
        }
    }
}

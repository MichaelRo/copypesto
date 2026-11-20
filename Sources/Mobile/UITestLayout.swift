// SPDX-License-Identifier: MIT
#if DEBUG
import Foundation
import PestoCore
import SwiftUI

/// A `-UITestMode` launch with `PESTO_UITEST_SIZE_CLASS` (`compact` or `regular`) forces the library's width class and
/// carries a small control that flips it, because XCUITest cannot resize an iPad window. Flipping it switches between
/// the phone's and the pad's layout exactly as a real change of width does, with the same views torn down and built.
enum UITestLayout {
    static let environmentKey = "PESTO_UITEST_SIZE_CLASS"
    static let swapIdentifier = "uitest-swap-layout"
    static let detailSwapIdentifier = "uitest-swap-layout-detail"

    static var initialSizeClass: UserInterfaceSizeClass? {
        guard LaunchMode.current == .uiTest else { return nil }
        return sizeClass(named: ProcessInfo.processInfo.environment[environmentKey])
    }

    static func sizeClass(named name: String?) -> UserInterfaceSizeClass? {
        switch name {
        case "compact": .compact
        case "regular": .regular
        default: nil
        }
    }

    @MainActor @ViewBuilder
    static func swapControl(
        library: LibraryModel, actual: UserInterfaceSizeClass?, identifier: String = swapIdentifier
    )
    -> some View {
        if initialSizeClass != nil {
            let current = library.forcedSizeClass ?? actual
            Button {
                library.forcedSizeClass = current == .compact ? .regular : .compact
            } label: {
                Color.primary.opacity(0.001).frame(width: 28, height: 28).contentShape(.rect)
            }
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(Text(verbatim: current == .compact ? "compact" : "regular"))
        }
    }
}
#endif

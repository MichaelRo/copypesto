// SPDX-License-Identifier: MIT
import SwiftUI
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

@Suite("The library root picks its layout from the width class and its sidebar from the width")
@MainActor
struct LibraryResizeHostingTests {
    struct Window: CustomTestStringConvertible {
        let width: CGFloat
        let sizeClass: UIUserInterfaceSizeClass
        let showsSplitView: Bool
        let columns: NavigationSplitViewVisibility
        var testDescription: String {
            "\(Int(width)) pt, \(sizeClass == .regular ? "regular" : "compact")"
        }
    }

    nonisolated static let windows: [Window] = [
        Window(width: 375, sizeClass: .compact, showsSplitView: false, columns: .detailOnly),
        Window(width: 700, sizeClass: .regular, showsSplitView: true, columns: .detailOnly),
        Window(width: 800, sizeClass: .regular, showsSplitView: true, columns: .all)
    ]

    private struct Hosted {
        let host: UIHostingController<AnyView>
        let window: UIWindow
        let library: LibraryModel
        let state: MobileTestLibrary
    }

    private func splitViews(in controller: UIViewController) -> [UISplitViewController] {
        let own = (controller as? UISplitViewController).map { [$0] } ?? []
        return own + controller.children.flatMap(splitViews(in:))
    }

    private func host(width: CGFloat, sizeClass: UIUserInterfaceSizeClass) async throws -> Hosted {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "the hosted test runs inside the app, which has a window scene"
        )
        let state = try await MobileTestLibrary()
        let library = LibraryModel()
        #if DEBUG
        library.forcedSizeClass = nil
        #endif
        let host = UIHostingController(rootView: AnyView(LibraryRootView(library: library).environment(state.state)))
        host.traitOverrides.horizontalSizeClass = sizeClass
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        window.rootViewController = host
        window.isHidden = false
        return Hosted(host: host, window: window, library: library, state: state)
    }

    /// Lets UIKit finish the split view's transitions, which write their column visibility back to the binding.
    private func settle(_ hosted: Hosted) async throws {
        for _ in 0..<25 {
            hosted.window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test(
        "a compact window shows the phone layout, a regular one the sidebar layout, collapsed under 800 points",
        arguments: windows
    )
    func whenHostedAtAWidth_thenTheLayoutAndColumnsFollow(_ window: Window) async throws {
        let hosted = try await host(width: window.width, sizeClass: window.sizeClass)
        defer { hosted.window.isHidden = true }

        try await settle(hosted)

        #expect(!splitViews(in: hosted.host).isEmpty == window.showsSplitView)
        #expect(hosted.library.columns == window.columns)
    }

    @Test("unfolding a 700 point window to a regular width brings the sidebar layout with the sidebar collapsed")
    func whenACompactWindowBecomesRegular_thenTheSidebarStartsCollapsed() async throws {
        let hosted = try await host(width: 700, sizeClass: .compact)
        defer { hosted.window.isHidden = true }
        try await settle(hosted)
        #expect(splitViews(in: hosted.host).isEmpty)

        hosted.host.traitOverrides.horizontalSizeClass = .regular
        try await settle(hosted)

        #expect(!splitViews(in: hosted.host).isEmpty)
        #expect(hosted.library.columns == .detailOnly)
    }
}

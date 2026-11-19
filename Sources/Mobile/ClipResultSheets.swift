// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The sheets a clip's menu opens over the library: what Decode JWT read and an AI answer. A sheet cannot present over
/// one from below, so the library presents them unless a clip's detail is a sheet over it, and the detail presents
/// them then.
struct ClipResultSheets: ViewModifier {
    enum Host {
        case library
        /// A clip's detail that is itself a sheet (a compact width). On a regular width the detail is the inspector, a
        /// column beside the library, and the library presents.
        case detail(isSheet: Bool)
    }

    let host: Host
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var presents: Bool {
        switch host {
        case .library: !(library.openClipID != nil && sizeClass == .compact)
        case let .detail(isSheet): isSheet
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: jwtBinding) {
                if let result = appState.decodedJWT {
                    JWTDecodeSheet(result: result).presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: aiBinding) { AIResultSheet().presentationDetents([.medium, .large]) }
    }

    private var aiBinding: Binding<Bool> {
        Binding(get: { presents && appState.showsAI }, set: { if !$0 { appState.closeAI() } })
    }

    private var jwtBinding: Binding<Bool> {
        Binding(get: { presents && appState.decodedJWT != nil }, set: { if !$0 { appState.decodedJWT = nil } })
    }
}

extension View {
    func clipResultSheets(_ host: ClipResultSheets.Host) -> some View {
        modifier(ClipResultSheets(host: host))
    }
}

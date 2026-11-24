// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// The compact width: one stack with the chip row over the grid, search where iOS puts it for a single stack, and a
/// clip's detail in a sheet.
struct PhoneLibraryView: View {
    let store: HistoryStore
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var containerWidth: CGFloat = 0
    @State private var settingsDragOffset: CGFloat?

    var body: some View {
        @Bindable var library = library
        ZStack {
            NavigationStack {
                LibraryGrid(store: store, showsChipRow: true)
                    .navigationTitle(LibraryTitle.text(for: library.filter.scope, collections: collections))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { LibraryToolbar(showsSettings: true) }
            }
            .searchable(text: $library.query, isPresented: $library.isSearching, prompt: Text("Search clips"))
            .onSubmit(of: .search) {
                if AskHeuristic.returnAsks(text: library.query, resultCount: library.visibleResultCount) {
                    library.startAsk(
                        using: { await appState.askPesto($0) },
                        isLocked: { appState.isHistoryLockedNow() }
                    )
                }
            }
            .onChange(of: library.query) { _, newValue in
                if library.isAsking, newValue != library.activeAskSentence { library.cancelAsk() }
            }
            .onChange(of: library.isSearching) { _, searching in if !searching { library.endSearch() } }
            .accessibilityHidden(library.showsSettings)

            if isSettingsVisible {
                Color.black
                    .opacity(scrimOpacity)
                    .ignoresSafeArea()
                    .onTapGesture(perform: closeSettings)
                    .zIndex(1)
                    .transition(.opacity)
                SettingsSheet(onClose: closeSettings)
                    .offset(x: settingsSlideOffset)
                    .zIndex(2)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    .simultaneousGesture(settingsCloseGesture)
            }
        }
        .animation(Motion.animation(.pestoQuick), value: library.showsSettings)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .simultaneousGesture(settingsPullGesture)
        .sheet(isPresented: detailBinding) {
            if let id = library.openClipID {
                ClipDetailView(store: store, itemID: id, isSheet: true)
                    .presentationDetents([.medium, .large])
            }
        }
        .libraryPresentations(presentsSettingsSheet: false)
        .onChange(of: library.showsSettings) { _, shown in
            if !shown {
                library.settingsDestination = nil
                if appState.takeWelcomeAgainRequest() { appState.showWelcomeAgain() }
            }
        }
    }

    private var isSettingsVisible: Bool {
        library.showsSettings || (settingsDragOffset != nil && containerWidth > 0)
    }

    private var settingsSlideOffset: CGFloat {
        if library.showsSettings { return 0 }
        guard let settingsDragOffset, containerWidth > 0, !reduceMotion else { return 0 }
        let remaining = max(0, containerWidth - settingsDragOffset)
        return layoutDirection == .rightToLeft ? remaining : -remaining
    }

    private var scrimOpacity: Double {
        if library.showsSettings { return 0.28 }
        guard let settingsDragOffset, containerWidth > 0 else { return 0 }
        return 0.28 * min(1, max(0, settingsDragOffset / containerWidth))
    }

    private func closeSettings() {
        library.showsSettings = false
    }

    private var settingsPullGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                guard !library.isSelecting, !library.isSearching, !library.showsSettings,
                      library.openClipID == nil else { return }
                if let activeOffset = SettingsEdgeSwipe.inwardDragOffset(
                    startX: value.startLocation.x,
                    translation: value.translation,
                    width: containerWidth,
                    isRTL: layoutDirection == .rightToLeft,
                    alreadyEngaged: settingsDragOffset != nil
                ) {
                    settingsDragOffset = activeOffset
                }
            }
            .onEnded { value in
                defer {
                    if !library.showsSettings, settingsDragOffset != nil {
                        withAnimation(Motion.animation(.pestoQuick)) {
                            settingsDragOffset = nil
                        }
                    }
                }
                guard !library.isSelecting, !library.isSearching, !library.showsSettings,
                      library.openClipID == nil else { return }
                let isRTL = layoutDirection == .rightToLeft
                let startedLeading = SettingsEdgeSwipe.isLeadingEdgeStart(
                    value.startLocation.x, width: containerWidth, isRTL: isRTL
                )
                let shouldOpenFromDrag = startedLeading && settingsDragOffset != nil && (
                    SettingsEdgeSwipe.shouldOpen(
                        startX: value.startLocation.x,
                        translation: value.predictedEndTranslation,
                        width: containerWidth,
                        isRTL: isRTL
                    ) || SettingsEdgeSwipe.shouldOpen(
                        startX: value.startLocation.x,
                        translation: value.translation,
                        width: containerWidth,
                        isRTL: isRTL
                    )
                )
                if shouldOpenFromDrag || SettingsEdgeSwipe.shouldOpen(
                    startX: value.startLocation.x,
                    translation: value.translation,
                    width: containerWidth,
                    isRTL: isRTL
                ) {
                    withAnimation(Motion.animation(.pestoQuick)) {
                        settingsDragOffset = nil
                        library.showsSettings = true
                    }
                }
            }
    }

    private var settingsCloseGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard library.showsSettings else { return }
                if SettingsEdgeSwipe.shouldClose(
                    translation: value.translation,
                    isRTL: layoutDirection == .rightToLeft
                ) {
                    closeSettings()
                }
            }
    }

    private var detailBinding: Binding<Bool> {
        Binding(get: { library.openClipID != nil }, set: { if !$0 { library.openClipID = nil } })
    }
}

enum SettingsEdgeSwipe {
    static let edgeInset: CGFloat = 32
    static let minimumPull: CGFloat = 56
    static let horizontalDominance: CGFloat = 1.5

    static func isLeadingEdgeStart(_ startX: CGFloat, width: CGFloat, isRTL: Bool) -> Bool {
        guard width > 0 else { return false }
        return isRTL ? startX >= width - edgeInset : startX <= edgeInset
    }

    static func inwardDragOffset(
        startX: CGFloat, translation: CGSize, width: CGFloat, isRTL: Bool, alreadyEngaged: Bool = false
    )
    -> CGFloat? {
        guard isLeadingEdgeStart(startX, width: width, isRTL: isRTL) else { return nil }
        let inwardPull = isRTL ? -translation.width : translation.width
        guard inwardPull > 0 else { return nil }
        if !alreadyEngaged, abs(translation.width) <= abs(translation.height) * horizontalDominance {
            return nil
        }
        return min(width, inwardPull)
    }

    static func shouldOpen(startX: CGFloat, translation: CGSize, width: CGFloat, isRTL: Bool) -> Bool {
        guard isLeadingEdgeStart(startX, width: width, isRTL: isRTL) else { return false }
        let inwardPull = isRTL ? -translation.width : translation.width
        return inwardPull >= minimumPull && abs(translation.width) > abs(translation.height) * horizontalDominance
    }

    static func shouldClose(translation: CGSize, isRTL: Bool) -> Bool {
        let outwardPull = isRTL ? translation.width : -translation.width
        return outwardPull >= minimumPull && abs(translation.width) > abs(translation.height) * horizontalDominance
    }
}

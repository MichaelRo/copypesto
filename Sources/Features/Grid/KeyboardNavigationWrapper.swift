// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

struct KeyboardNavigationWrapper<Content: View>: View {
    @Binding var focusedIndex: Int
    let itemCount: Int
    var isSearchActive: Bool = false
    var isOverlayVisible: Bool = false
    var isEditingCollection: Bool = false
    var isConfirming: Bool = false
    var isLocked: Bool = false
    var onEscape: (() -> Void)?
    var onDismissShelf: (() -> Void)?
    var onReturn: (() -> Void)?
    var onSpace: (() -> Void)?
    var onCharacterTyped: ((String) -> Void)?
    var onEscapeFromSearch: (() -> Void)?
    var onArrowKey: (() -> Void)?
    var onPrevPinboard: (() -> Void)?
    var onNextPinboard: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSelectAll: (() -> Void)?
    var onReturnFromSearch: (() -> Void)?
    var onReturnPlainFromSearch: (() -> Void)?
    var cardSpan: CGFloat = 0
    var onOpenSettings: (() -> Void)?
    var onNewCollection: (() -> Void)?
    var onPasteAllSelected: (() -> Void)?
    var onPasteSelectedOneByOne: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var searchTextIsEmpty: (() -> Bool)?
    var onPasteNth: ((Int) -> Void)?
    var onShowActions: (() -> Void)?
    var onCopy: (() -> Void)?
    var onAskFromSearch: (() -> Void)?
    var onShowHidden: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onCancelConfirmation: (() -> Void)?
    var onSearch: (() -> Void)?
    var onSaveImage: (() -> Bool)?
    var onQuickLook: (() -> Void)?
    var onReturnPlain: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var coordinator = KeyNavCoordinator()
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        content()
            .background(HostWindowReader { coordinator.hostWindow = $0 })
            .onAppear {
                refreshCoordinator()
                coordinator.start()
            }
            .onDisappear { coordinator.stop() }
            .onChange(of: isSearchActive) { _, active in coordinator.isSearchActive = active }
            .onChange(of: isOverlayVisible) { _, visible in coordinator.isOverlayVisible = visible }
            .onChange(of: isEditingCollection) { _, editing in coordinator.isEditingCollection = editing }
            .onChange(of: isConfirming) { _, confirming in coordinator.isConfirming = confirming }
            .onChange(of: isLocked) { _, locked in coordinator.isLocked = locked }
            .onChange(of: itemCount) { _, _ in refreshCoordinator() }
    }

    private func bindMovement() {
        let binding = $focusedIndex
        let count = itemCount
        let arrowKey = onArrowKey
        coordinator.onLeft = {
            guard count > 0 else { return }
            binding.wrappedValue = max(0, binding.wrappedValue - 1)
            arrowKey?()
        }
        coordinator.onRight = {
            guard count > 0 else { return }
            binding.wrappedValue = min(count - 1, binding.wrappedValue + 1)
            arrowKey?()
        }
        coordinator.cardSpan = cardSpan
        coordinator.usesRightToLeft = layoutDirection == .rightToLeft
        coordinator.onPage = { pages in
            guard count > 0 else { return }
            binding.wrappedValue = min(max(0, binding.wrappedValue + pages), count - 1)
            arrowKey?()
        }
        coordinator.onFirst = {
            guard count > 0 else { return }
            binding.wrappedValue = 0
            arrowKey?()
        }
        coordinator.onLast = {
            guard count > 0 else { return }
            binding.wrappedValue = count - 1
            arrowKey?()
        }
    }

    private func bindFilterChips() {
        coordinator.onFilterChipMove = { [appState] delta in
            MainActor.assumeIsolated { appState.moveFilterChipCursor(by: delta) }
        }
        coordinator.onFilterChipToggle = { [appState] in
            MainActor.assumeIsolated { appState.toggleFilterChipAtCursor() }
        }
        coordinator.onFilterChipRelease = { [appState] in
            MainActor.assumeIsolated { appState.releaseFilterChipCursor() }
        }
    }

    private func refreshCoordinator() {
        coordinator.isSearchActive = isSearchActive
        coordinator.isOverlayVisible = isOverlayVisible
        coordinator.isEditingCollection = isEditingCollection
        coordinator.isConfirming = isConfirming
        coordinator.isLocked = isLocked
        bindMovement()
        coordinator.onEscape = onEscape
        coordinator.onDismissShelf = onDismissShelf
        coordinator.onReturn = onReturn
        coordinator.onSpace = onSpace
        coordinator.onCharacterTyped = onCharacterTyped
        coordinator.onEscapeFromSearch = onEscapeFromSearch
        coordinator.onPrevPinboard = onPrevPinboard
        coordinator.onNextPinboard = onNextPinboard
        coordinator.onDelete = onDelete
        coordinator.onSelectAll = onSelectAll
        coordinator.onReturnFromSearch = onReturnFromSearch
        coordinator.onReturnPlainFromSearch = onReturnPlainFromSearch
        coordinator.onUnlock = { [appState] in Task { await appState.performBiometricUnlock() } }
        coordinator.onOpenSettings = onOpenSettings
        coordinator.onNewCollection = onNewCollection
        coordinator.onPasteAllSelected = onPasteAllSelected
        coordinator.onPasteSelectedOneByOne = onPasteSelectedOneByOne
        coordinator.onUndo = onUndo
        coordinator.onRedo = onRedo
        coordinator.searchTextIsEmpty = searchTextIsEmpty
        coordinator.onPasteNth = onPasteNth
        coordinator.onShowActions = onShowActions
        coordinator.onCopy = onCopy
        coordinator.onAskFromSearch = onAskFromSearch
        coordinator.onShowHidden = onShowHidden
        coordinator.onConfirm = onConfirm
        coordinator.onCancelConfirmation = onCancelConfirmation
        coordinator.onSearch = onSearch
        coordinator.onSaveImage = onSaveImage
        coordinator.onQuickLook = onQuickLook
        coordinator.onReturnPlain = onReturnPlain
        bindFilterChips()
    }
}

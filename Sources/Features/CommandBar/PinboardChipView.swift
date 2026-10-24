// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI
import UniformTypeIdentifiers

/// Wraps a single CollectionChip with its own editing popover state so that
/// the edit UI floats over the overlay without distorting the NSPanel layout.
struct PinboardChipView: View {
    @Environment(\.pestoAccent) private var accent
    var pinboard: Pinboard
    var isSelected: Bool
    var onSelect: () -> Void
    var onDuplicate: () -> Void
    var onExport: () -> Void
    var onSave: (String, String, String) -> Void
    var onDelete: () -> Void
    var onDrop: (() -> Void)?
    /// Move Left (-1) and Move Right (+1): the same reorder as dragging, for the menu and VoiceOver.
    var onMove: ((Int) -> Void)?
    var canMoveLeft = false
    var canMoveRight = false
    var insertionSide: CollectionReorder.Side?

    @Environment(AppState.self) private var appState: AppState
    @State private var isEditing = false
    @State private var isDropTarget = false

    private var isDragSource: Bool {
        appState.draggingPinboardID == pinboard.id
    }

    var body: some View {
        CollectionChip(
            name: pinboard.name,
            symbolName: pinboard.symbolName,
            color: Color(hex: pinboard.colorHex) ?? accent,
            isSelected: isSelected,
            onSelect: onSelect
        )
        // The chip being dragged stays in the row at 35% opacity so the row never changes width, and one accent bar
        // marks the gap where it will land (`ChipRowDropDelegate`).
        .opacity(isDragSource ? 0.35 : 1)
            .overlay(alignment: insertionSide == .before ? .leading : .trailing) {
                if let insertionSide {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(accent)
                        .frame(width: 2, height: 20)
                        .offset(x: insertionSide == .before ? -5 : 5)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ChipFramesKey.self, value: [pinboard.id: proxy.frame(in: .named(ChipFramesKey.space))]
                    )
                }
            }
            .overlay {
                if isDropTarget, appState.isDragging, appState.draggingPinboardID == nil {
                    Capsule().strokeBorder(
                        Color(hex: pinboard.colorHex) ?? accent,
                        lineWidth: 1.5
                    )
                }
            }
            .onDrag {
                appState.isDragging = true
                appState.draggingPinboardID = pinboard.id
                return NSItemProvider(object: pinboard.id.uuidString as NSString)
            } preview: {
                HStack(spacing: 4) {
                    CollectionIcon(symbolName: pinboard.symbolName)
                        .foregroundStyle(Color(hex: pinboard.colorHex) ?? accent)
                    Text(pinboard.name).font(.callout)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.opaqueSurface))
                .overlay(Capsule().strokeBorder(accent, lineWidth: 1))
                .opacity(0.9)
                .scaleEffect(Motion.reduceMotion ? 1 : 1.04)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            }
            .onDrop(
                of: [UTType.text, UTType.data],
                delegate: ChipDropDelegate(appState: appState, isTargeted: $isDropTarget, onClipDrop: { onDrop?() })
            )
            .contextMenu {
                Button("Edit…") { isEditing = true }
                Button("Duplicate") { onDuplicate() }
                Button("Export Collection\u{2026}") { onExport() }
                Divider()
                Button("Move Left") { onMove?(-1) }.disabled(!canMoveLeft)
                Button("Move Right") { onMove?(1) }.disabled(!canMoveRight)
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }
            .accessibilityAction(named: "Edit") { isEditing = true }
            .accessibilityAction(named: "Duplicate") { onDuplicate() }
            .accessibilityAction(named: "Export") { onExport() }
            .accessibilityAction(named: "Delete") { onDelete() }
            .accessibilityAction(named: "Move Left") { if canMoveLeft { onMove?(-1) } }
            .accessibilityAction(named: "Move Right") { if canMoveRight { onMove?(1) } }
            .help("\(pinboard.name) — right-click for options")
            .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                CollectionEditPopover(
                    existing: pinboard,
                    onSave: { name, symbol, colorHex in
                        onSave(name, symbol, colorHex)
                    },
                    onDelete: onDelete
                )
                .environment(appState)
            }
    }
}

/// A clip dragged over a collection chip keeps the collection's ring. A chip dragged over it is not this delegate's: it
/// refuses, and the row's delegate answers (`ChipRowDropDelegate`), so the cursor never shows "not allowed" between
/// chips.
private struct ChipDropDelegate: DropDelegate {
    let appState: AppState
    @Binding var isTargeted: Bool
    let onClipDrop: () -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        appState.draggingPinboardID == nil
    }

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        defer {
            isTargeted = false
            appState.isDragging = false
        }
        guard appState.draggingItemID != nil else { return false }
        onClipDrop()
        appState.draggingItemID = nil
        return true
    }
}

/// The frames of the collection chips, in the row's own coordinate space.
struct ChipFramesKey: PreferenceKey {
    static let space = "collectionChipRow"
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// One drop for the whole row of chips, so a dragged chip is accepted (a move) wherever the pointer is in the row. The
/// row
/// shows the new order live: the other chips slide around the dragged chip's empty slot, and nothing looks like a
/// target.
struct ChipRowDropDelegate: DropDelegate {
    let appState: AppState
    let baseOrder: [UUID]
    let frames: [UUID: CGRect]
    @Binding var frozenFrames: [UUID: CGRect]?
    @Binding var liveOrder: [UUID]?
    @Binding var insertionBar: CollectionReorder.InsertionBar?
    let onCommit: ([UUID]) -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        appState.draggingPinboardID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let source = appState.draggingPinboardID else { return nil }
        let slots = frozenFrames ?? frames
        if frozenFrames == nil { frozenFrames = frames }
        let others = baseOrder.filter { $0 != source }
        let mids = others.compactMap { slots[$0]?.midX }
        guard mids.count == others.count else { return DropProposal(operation: .move) }
        let current = (liveOrder ?? baseOrder).firstIndex(of: source) ?? 0
        let index = CollectionReorder.insertionIndex(slotMidXs: mids, pointerX: info.location.x, currentIndex: current)
        let order = CollectionReorder.order(baseOrder, moving: source, toIndex: index)
        let bar = CollectionReorder.insertionBar(baseOrder, moving: source, toIndex: index)
        if order != liveOrder { liveOrder = order }
        if bar != insertionBar { insertionBar = bar }
        return DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        liveOrder = nil
        insertionBar = nil
        frozenFrames = nil
    }

    func performDrop(info _: DropInfo) -> Bool {
        defer {
            liveOrder = nil
            insertionBar = nil
            frozenFrames = nil
            appState.isDragging = false
            appState.draggingPinboardID = nil
        }
        guard appState.draggingPinboardID != nil, let order = liveOrder, order != baseOrder else { return false }
        onCommit(order)
        return true
    }
}

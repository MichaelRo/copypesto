// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Context menu

extension ClipboardCard {
    /// A card covered for a screen share offers only `CardMenuItem.coveredAllowed` (ADR 0028).
    func offers(_ menuItem: CardMenuItem) -> Bool {
        menuItem.isOffered(covered: isCoveredForPrivacy)
    }

    @ViewBuilder
    var cardContextMenu: some View {
        if offers(.paste), actions.paste != nil {
            Button {
                actions.paste?(item)
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut(.return, modifiers: [])
        }
        if offers(.pastePlain), actions.pasteAs != nil, ShelfKeyGate.plainPasteAllowed(for: item.type) {
            Button {
                actions.pasteAs?(item, .stripFormatting)
            } label: {
                Label("Paste as Plain Text", systemImage: TextTransform.stripFormatting.symbolName)
            }
            .keyboardShortcut(.return, modifiers: .shift)
        }
        if offers(.copy) {
            Button {
                actions.copy?(item)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)
        }

        if offers(.copyLinkPreview), item.type == .url, item.sensitivity == nil, !concealment.isConcealed {
            if let pageTitle = item.ogTitle, !pageTitle.isEmpty, actions.copyText != nil {
                Button {
                    actions.copyText?(item, pageTitle)
                } label: {
                    Label("Copy Page Title", systemImage: "text.quote")
                }
            }
            if let image = urlOGImage, actions.copyImage != nil {
                Button {
                    actions.copyImage?(item, image)
                } label: {
                    Label("Copy Preview Image", systemImage: "photo")
                }
            } else if let thumbData = item.ogImageThumbnail, !thumbData.isEmpty, actions.copyImageData != nil {
                Button {
                    actions.copyImageData?(item, thumbData)
                } label: {
                    Label("Copy Preview Image", systemImage: "photo")
                }
            }
        }

        if item.sensitivity == nil {
            // A covered card is read with Show (or once screen sharing stops), not Quick Look.
            if offers(.quickLook), concealment.allowsQuickLook {
                Button {
                    actions.quickLook?(item)
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .keyboardShortcut("y", modifiers: .command)
            }
        } else {
            // A hidden clip is read with Show, not Quick Look: one way in, one place that asks first.
            if canRevealHidden, offers(.revealSecret) {
                Button {
                    toggleReveal()
                } label: {
                    Label(
                        revealedSecret == nil ? "Show" : "Hide",
                        systemImage: revealedSecret == nil ? "eye" : "eye.slash"
                    )
                }
                .keyboardShortcut("e", modifiers: .command)
                if offers(.decodeJWT), item.sensitivity == .jwt, concealment.allowsDecode, actions.decodeJWT != nil {
                    Button {
                        decodeJWT()
                    } label: {
                        Label("Decode JWT", systemImage: "curlybraces")
                    }
                }
            }
        }

        if offers(.saveImage), item.type == .image, concealment.allowsDrag, actions.saveImage != nil {
            Button {
                actions.saveImage?(item)
            } label: {
                Label("Save Image", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        if offers(.colorCopyFormats), item.type == .color, item.sensitivity == nil, actions.copyText != nil,
           let color = ColorLiteralParser.firstColor(in: item.displayPreviewText)
        {
            Menu {
                ForEach(ColorCopyFormat.allCases, id: \.self) { format in
                    Button(format.title) { actions.copyText?(item, format.string(for: color)) }
                }
            } label: {
                Label("Copy As", systemImage: "eyedropper")
            }
        }

        if offers(.openLink), item.type == .url {
            let link = LinkOpenPolicy.action(for: item.displayPreviewText)
            if let title = LinkOpener.title(for: link) {
                Button {
                    LinkOpener.perform(link)
                } label: {
                    Label(title, systemImage: LinkOpener.symbol(for: link))
                }
            }
        }

        if offers(.showInFinder), item.type == .file, concealment.allowsQuickLook {
            let files = FileClip.revealable(inText: item.displayPreviewText) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            if !files.isEmpty {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(files)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
        }

        if offers(.moveToCollection), actions.moveToCollection != nil, !availableCollections.isEmpty {
            Divider()

            Menu {
                if item.collectionID != nil {
                    Button {
                        actions.moveToCollection?(item, nil)
                    } label: {
                        Label("All (Remove from Collection)", systemImage: "tray.full")
                    }
                    Divider()
                }
                ForEach(availableCollections, id: \.id) { collection in
                    Button {
                        actions.moveToCollection?(item, collection.id)
                    } label: {
                        Label {
                            Text(collection.name)
                        } icon: {
                            CollectionIcon(symbolName: collection.symbolName)
                        }
                    }
                    .disabled(item.collectionID == collection.id)
                }
            } label: {
                Label("Move to Collection", systemImage: "folder")
            }
        }

        Divider()

        if offers(.pin), actions.togglePin != nil {
            Button {
                actions.togglePin?(item)
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
        }

        if offers(.rename) {
            Button {
                renameText = item.customTitle ?? ""
                isRenamingTitle = true
            } label: {
                Label("Rename\u{2026}", systemImage: "pencil")
            }
        }

        if offers(.note) {
            Button {
                noteText = item.userNote ?? ""
                showNotePopover = true
            } label: {
                Label(item.userNote == nil ? "Add Note\u{2026}" : "Edit Note\u{2026}", systemImage: "note.text")
            }
        }

        if offers(.icon), item.offersCustomIcon {
            Button {
                showIconPopover = true
            } label: {
                Label(
                    item.customSymbolName == nil ? "Change Icon\u{2026}" : "Edit Icon\u{2026}",
                    systemImage: "app.dashed"
                )
            }
        }

        if offers(.tag) {
            Button {
                tagText = ""
                showTagPopover = true
            } label: {
                Label("Add Tag\u{2026}", systemImage: "tag")
            }
        }

        if offers(.clearCustomizations),
           item.customTitle != nil || item.userNote != nil || item.customSymbolName != nil
        {
            Button(role: .destructive) {
                edit { clip in
                    clip.customTitle = nil
                    clip.userNote = nil
                    clip.customSymbolName = nil
                }
            } label: {
                Label("Clear Customizations", systemImage: "trash")
            }
        }

        Divider()

        let pasteAsTransforms = TextTransform.available(for: item.type)
        if !pasteAsTransforms.isEmpty {
            if offers(.copyTransformed), actions.copyTransformed != nil {
                Menu {
                    if !concealment.isConcealed {
                        StructuredTransformRows(
                            item: item, offered: actions.structuredTransforms, perform: actions.copyTransformed
                        )
                    }
                    ForEach(pasteAsTransforms, id: \.self) { transform in
                        Button {
                            actions.copyTransformed?(item, transform)
                        } label: {
                            Label(transform.rawValue, systemImage: transform.symbolName)
                        }
                    }
                } label: {
                    Label("Copy As\u{2026}", systemImage: "doc.on.doc.badge.gearshape")
                }
            }

            if offers(.pasteTransformed), actions.pasteAs != nil {
                Menu {
                    if !concealment.isConcealed {
                        StructuredTransformRows(
                            item: item, offered: actions.structuredTransforms, perform: actions.pasteAs
                        )
                    }
                    ForEach(pasteAsTransforms.filter { $0 != .stripFormatting }, id: \.self) { transform in
                        Button {
                            actions.pasteAs?(item, transform)
                        } label: {
                            Label(transform.rawValue, systemImage: transform.symbolName)
                        }
                    }
                } label: {
                    Label("Paste As\u{2026}", systemImage: "text.badge.chevron.right")
                }
            }
        }

        if offers(.entityActions), item.type == .text || item.type == .code, let onEntityAction = actions.entityAction {
            EntityMenuSection(text: item.gridPreview, onAction: onEntityAction)
        }

        Divider()

        let aiActions = AIAction.actions(for: item.type)
        if offers(.aiActions), !aiActions.isEmpty, concealment.allowsAIActions, let onAIAction = actions.aiAction {
            AIActionsMenuSection(actions: aiActions, onAction: { onAIAction(item, $0) })
        }

        if isPrivacyBlurred {
            Button {
                if isCoveredForPrivacy { reveal() } else { hideAgain() }
            } label: {
                Label(
                    isCoveredForPrivacy ? "Show" : "Hide Again",
                    systemImage: isCoveredForPrivacy ? "eye" : "eye.slash"
                )
            }
            .keyboardShortcut("e", modifiers: .command)
        }

        if offers(.markSensitive), let toggleSensitive = actions.toggleSensitive {
            if isBlurredAsSensitive {
                Button {
                    reveal()
                } label: {
                    Label("Show", systemImage: "eye")
                }
                .keyboardShortcut("e", modifiers: .command)
            }
            if item.isNSFW, nsfwMode.blursCards, isNSFWRevealed || revealedFromOutside {
                Button {
                    hideAgain()
                } label: {
                    Label("Hide Again", systemImage: "eye.slash")
                }
                .keyboardShortcut("e", modifiers: .command)
            }
            Button {
                hideAgain()
                toggleSensitive(item)
            } label: {
                Label(
                    item.isNSFW ? "Mark as Not Sensitive" : "Mark as Sensitive",
                    systemImage: item.isNSFW ? "eye" : "eye.slash"
                )
            }
        }

        if offers(.setExpiry), actions.setExpiry != nil {
            Menu {
                Button { actions.setExpiry?(item, .distantPast) } label: {
                    Label("Burn After Paste", systemImage: "flame")
                }
                Button { actions.setExpiry?(item, .now + 3600) } label: {
                    Label("Expire in 1 Hour", systemImage: "clock")
                }
                Button { actions.setExpiry?(item, .now + 86_400) } label: {
                    Label("Expire in 24 Hours", systemImage: "clock")
                }
                Button { actions.setExpiry?(item, .now + 7 * 86_400) } label: {
                    Label("Expire in 1 Week", systemImage: "clock")
                }
                if item.expiresAt != nil {
                    Divider()
                    Button(role: .destructive) { actions.setExpiry?(item, nil) } label: {
                        Label("Remove Expiry", systemImage: "clock.badge.xmark")
                    }
                }
            } label: {
                Label("Set Expiry", systemImage: "clock")
            }
        }

        if offers(.assignShortcut), actions.assignHotkey != nil {
            Menu {
                ForEach(1...9, id: \.self) { slot in
                    let taken = unavailableHotkeySlots.contains(slot)
                    let current = item.pinnedHotkeyIndex == slot
                    Button {
                        actions.assignHotkey?(item, current ? nil : slot)
                    } label: {
                        Label(
                            "⌃\(slot)\(current ? "  ✓" : taken ? "  (taken)" : "")",
                            systemImage: taken ? "keyboard.badge.ellipsis" : "keyboard"
                        )
                    }
                    .disabled(taken && !current)
                }
                if item.pinnedHotkeyIndex != nil {
                    Divider()
                    Button(role: .destructive) { actions.assignHotkey?(item, nil) } label: {
                        Label("Remove Shortcut", systemImage: "keyboard.badge.minus")
                    }
                }
            } label: {
                Label("Paste Shortcut", systemImage: "keyboard")
            }
        }

        Divider()
        if offers(.delete) {
            Button(role: .destructive) {
                actions.delete?(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}

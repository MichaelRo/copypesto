// SPDX-License-Identifier: MIT
import AuthenticationServices
import PestoCore
import SwiftData
import SwiftUI
import UIKit

struct KeyboardSettingsView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.pestoAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @AppStorage(Setting.keyboardCollections) private var storedCollections: String
    @AppStorage(Setting.hiddenMobileCollections) private var hiddenCollections: String
    @AppStorage(Setting.keyboardReturnsAfterInsert) private var keyboardReturns: Bool
    @AppStorage(Setting.keyboardSize) private var keyboardSize: String
    @State private var showsSetupGuide = false
    @State private var isAutoFillEnabled = false
    @State private var isKeyboardAdded = false
    @State private var previewEntries = KeyboardPreviewSamples.entries()

    private var parsedOptions: QuickInsertSelection.Options {
        QuickInsertSelection.Options(
            storedCollections: storedCollections,
            hiddenCollectionIDs: HiddenCollections.ids(from: hiddenCollections),
            lockedCollectionIDs: LockedCollections.current(),
            returnsAfterInsert: true
        )
    }

    private var collectionsSummary: String {
        let count = parsedOptions.resolvedCollections(from: collections).count
        switch parsedOptions.collectionMode {
        case .all:
            return count == 0
                ? String(localized: "Built-in only")
                : String(localized: "All collections")
        case .custom:
            return count == 0
                ? String(localized: "Built-in only")
                : String(localized: "\(count) added")
        }
    }

    private var setupButtonTitle: LocalizedStringKey {
        (isAutoFillEnabled && isKeyboardAdded)
            ? "Manage Keyboard & AutoFill\u{2026}"
            : "Set Up Keyboard & AutoFill\u{2026}"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("AutoFill") {
                    Text(isAutoFillEnabled ? "On" : "Off")
                        .foregroundStyle(isAutoFillEnabled ? Color.statusGood : .secondary)
                }
                LabeledContent("Pesto Keyboard") {
                    Text(isKeyboardAdded ? "Added" : "Not Added")
                        .foregroundStyle(isKeyboardAdded ? Color.statusGood : .secondary)
                }
                Button(setupButtonTitle) {
                    showsSetupGuide = true
                }
            } header: {
                Text("Status")
            } footer: {
                Text(
                    "AutoFill inserts clips in any text field. Pesto Keyboard also needs Allow Full Access " +
                        "turned on in iOS Settings."
                )
            }

            Section {
                NavigationLink {
                    KeyboardCollectionsView()
                } label: {
                    LabeledContent("Collections", value: collectionsSummary)
                }
            } header: {
                Text("Shown in Keyboard & AutoFill")
            } footer: {
                Text(
                    "All, Pinned, and Snippets (pinned clips with placeholders like {{date}}) appear " +
                        "first, followed by your collections."
                )
            }

            Section("Keyboard") {
                KeyboardSizePreview(
                    size: KeyboardSize(rawValue: keyboardSize) ?? .medium, entries: previewEntries,
                    theme: MobileAppState.widgetTheme(), showsKeys: true
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                Picker("Keyboard size", selection: $keyboardSize) {
                    Text("Small").tag(KeyboardSize.small.rawValue)
                    Text("Medium").tag(KeyboardSize.medium.rawValue)
                    Text("Large").tag(KeyboardSize.large.rawValue)
                }
                .onChange(of: keyboardSize) { _, newValue in
                    guard let size = KeyboardSize(rawValue: newValue) else { return }
                    if KeyboardSizeStore.current?.load()?.size != size {
                        try? KeyboardSizeStore.current?.save(size)
                        appState.writeQuickInsert()
                    }
                }
                Picker("After inserting a clip", selection: $keyboardReturns) {
                    Text("Return to my keyboard").tag(true)
                    Text("Stay in Pesto").tag(false)
                }
                .onChange(of: keyboardReturns) { appState.writeQuickInsert() }
            }
        }
        .tint(accent)
        .sheet(isPresented: $showsSetupGuide) {
            QuickInsertSetupSheet()
        }
        .onChange(of: showsSetupGuide) { _, shown in
            if !shown { Task { await refreshStatus() } }
        }
        .navigationTitle("Keyboard & AutoFill")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            MobileAppState.migrateQuickInsertSettingsIfNeeded()
            appState.reconcileKeyboardSize()
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.reconcileKeyboardSize()
                Task { await refreshStatus() }
            }
        }
    }

    private func refreshStatus() async {
        let state = await ASCredentialIdentityStore.shared.state()
        isAutoFillEnabled = state.isEnabled
        isKeyboardAdded = UITextInputMode.activeInputModes.contains { mode in
            (mode.value(forKey: "identifier") as? String)?.contains("net.copypesto.pesto") == true
        }
    }
}

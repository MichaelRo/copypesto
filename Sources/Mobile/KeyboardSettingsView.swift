// SPDX-License-Identifier: MIT
import AuthenticationServices
import PestoCore
import SwiftUI
import UIKit

struct KeyboardSettingsView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Setting.keyboardCollections) private var storedCollections: String
    @AppStorage(Setting.keyboardReturnsAfterInsert) private var keyboardReturns: Bool
    @AppStorage(Setting.keyboardSize) private var keyboardSize: String
    @State private var showsSetupGuide = false
    @State private var isAutoFillEnabled = false
    @State private var isKeyboardAdded = false
    @State private var autoFillStatusNote: String?

    private var chosenCollectionsCount: Int {
        QuickInsertSelection.Options(storedCollections: storedCollections, returnsAfterInsert: true).collectionIDs.count
    }

    private var collectionsSummary: String {
        chosenCollectionsCount == 0
            ? String(localized: "Built-in only")
            : String(localized: "\(chosenCollectionsCount) added")
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("AutoFill") {
                    Text(isAutoFillEnabled ? "On" : "Off")
                        .foregroundStyle(isAutoFillEnabled ? Color.statusGood : .secondary)
                }
                if isAutoFillEnabled {
                    Button("Open AutoFill Settings") {
                        Task {
                            await AutoFillSettings.openSettings()
                            await refreshStatus()
                        }
                    }
                } else {
                    Button("Turn On AutoFill\u{2026}") {
                        AppDefaults.store.set(true, for: Setting.autoFillEnabled)
                        AppDefaults.store.set(true, for: Setting.quickInsertEnabled)
                        appState.quickInsertSettingChanged()
                        Task {
                            let granted = await ASSettingsHelper.requestToTurnOnCredentialProviderExtension()
                            autoFillStatusNote = granted
                                ? String(localized: "AutoFill is enabled.")
                                : String(localized: "Opened Settings. Turn on Pesto under AutoFill & Passwords.")
                            if !granted {
                                await AutoFillSettings.openSettings()
                            }
                            await refreshStatus()
                        }
                    }
                }
                if let autoFillStatusNote {
                    Text(autoFillStatusNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Pesto Keyboard") {
                    Text(isKeyboardAdded ? "Added" : "Not Added")
                        .foregroundStyle(isKeyboardAdded ? Color.statusGood : .secondary)
                }
                Button("Set Up Keyboard & AutoFill\u{2026}") {
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
                Text("Shared")
            } footer: {
                Text(
                    "All, Pinned, and Snippets (pinned clips with placeholders like {{date}}) appear " +
                        "automatically when available. Add collections to show after them."
                )
            }

            Section("Keyboard") {
                Picker("Keyboard size", selection: $keyboardSize) {
                    Text("Small").tag(KeyboardSize.small.rawValue)
                    Text("Medium").tag(KeyboardSize.medium.rawValue)
                    Text("Large").tag(KeyboardSize.large.rawValue)
                }
                .onChange(of: keyboardSize) { appState.writeQuickInsert() }
                Picker("After inserting a clip", selection: $keyboardReturns) {
                    Text("Return to my keyboard").tag(true)
                    Text("Stay in Pesto").tag(false)
                }
                .onChange(of: keyboardReturns) { appState.writeQuickInsert() }
            }
        }
        .sheet(isPresented: $showsSetupGuide) {
            QuickInsertSetupSheet()
        }
        .navigationTitle("Keyboard & AutoFill")
        .onAppear {
            MobileAppState.migrateQuickInsertSettingsIfNeeded()
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
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

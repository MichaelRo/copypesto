// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

struct KeyboardSettingsView: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @AppStorage(Setting.keyboardReturnsAfterInsert) private var keyboardReturns: Bool
    @AppStorage(Setting.keyboardSize) private var keyboardSize: String

    var body: some View {
        Form {
            Section {
                NavigationLink("Keyboard collections") { KeyboardCollectionsView() }
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
                Button("Turn On AutoFill\u{2026}") {
                    AppDefaults.store.set(true, for: Setting.autoFillEnabled)
                    AppDefaults.store.set(true, for: Setting.quickInsertEnabled)
                    appState.writeQuickInsert()
                    Task { await AutoFillSettings.open() }
                }
            } header: {
                Text("Keyboard & AutoFill")
            } footer: {
                Text(
                    "In any text field, choose AutoFill in the edit menu and pick Pesto, or add Pesto\u{2019}s " +
                        "keyboard in Settings > General > Keyboard > Keyboards and allow Full Access."
                )
            }

            Section {
                Button("Open iOS Settings") {
                    _ = AppPasteboard.general.hasStrings
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } footer: {
                Text(
                    "To skip the iOS paste prompt when pasting into Pesto, set Paste from Other Apps to " +
                        "Allow in iOS Settings."
                )
            }
        }
        .navigationTitle("Keyboard & AutoFill")
        .onAppear {
            MobileAppState.migrateQuickInsertSettingsIfNeeded()
        }
    }
}

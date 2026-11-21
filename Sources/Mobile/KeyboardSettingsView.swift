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
            } header: {
                Text("Keyboard")
            } footer: {
                Text(
                    "AutoFill and Pesto\u{2019}s keyboard use a sealed set of non-secret text clips. Turn on " +
                        "Pesto in Settings > General > AutoFill & Passwords, or add it in Settings > General > " +
                        "Keyboard > Keyboards and allow Full Access."
                )
            }

            Section {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        }
        .navigationTitle("Keyboard & AutoFill")
        .onAppear {
            MobileAppState.migrateQuickInsertSettingsIfNeeded()
        }
    }
}

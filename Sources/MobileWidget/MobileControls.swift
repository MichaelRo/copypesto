// SPDX-License-Identifier: MIT
import AppIntents
import PestoCore
import SwiftUI
import WidgetKit

/// Opens Pesto without carrying or reading any clip.
struct OpenPestoIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pesto"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "pesto://open") else { throw CocoaError(.fileNoSuchFile) }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct OpenPestoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(AppIdentity.bundleID).open") {
            ControlWidgetButton(action: OpenPestoIntent()) {
                Label("Open Pesto", systemImage: "list.clipboard")
            }
        }
        .displayName("Open Pesto")
        .description("Opens your Pesto library.")
    }
}

struct AddClipboardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(AppIdentity.bundleID).add-clipboard") {
            ControlWidgetButton(action: AddClipboardToPestoIntent()) {
                Label("Add Clipboard", systemImage: "doc.on.clipboard")
            }
        }
        .displayName("Add Clipboard to Pesto")
        .description("Opens Pesto and saves what you copied.")
    }
}

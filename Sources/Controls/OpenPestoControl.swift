// SPDX-License-Identifier: MIT
import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center button that opens the shelf. It carries no data: pressing it opens `pesto://open`, which the app
/// already handles, so the extension never sees a clip.
@available(macOS 26.0, *)
struct OpenPestoIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pesto"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "pesto://open") ?? URL(fileURLWithPath: "/")))
    }
}

@available(macOS 26.0, *)
struct OpenPestoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "net.copypesto.pesto.open-shelf") {
            ControlWidgetButton(action: OpenPestoIntent()) {
                Label("Pesto", systemImage: "list.clipboard")
            }
        }
        .displayName("Open Pesto")
        .description("Shows your clipboard shelf.")
    }
}

@main
struct PestoControls: WidgetBundle {
    var body: some Widget {
        if #available(macOS 26.0, *) {
            OpenPestoControl()
        }
    }
}

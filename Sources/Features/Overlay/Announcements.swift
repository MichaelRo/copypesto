// SPDX-License-Identifier: MIT
import PestoCore

@MainActor
enum ToastAnnouncement {
    static func manualPaste(_ toast: ManualPasteToast = .pressCommandV) {
        switch toast {
        case .pressCommandV: Announcer.announce("Copied. Press \u{2318}V to paste.")
        case .autoPasteIsOff:
            Announcer
                .announce(
                    "Copied. Auto-paste is off. Press \u{2318}V to paste, or open Accessibility settings to turn it on."
                )
        }
    }
}

@MainActor
extension ToastAnnouncement {
    static func updatesUnavailable() {
        Announcer.announce("This build does not check for updates.")
    }

    static func upToDate() {
        Announcer.announce("Pesto is up to date.")
    }
}

/// The stack HUD is a panel that never takes focus, so its progress is spoken instead.
@MainActor
enum StackAnnouncement {
    static func progress(position: Int, count: Int, hint: String) {
        Announcer.announce("Paste One by One, clip \(position) of \(count). \(hint).")
    }

    static func complete() {
        Announcer.announce("Paste One by One complete")
    }
}

@MainActor
enum AIResultAnnouncement {
    static func announce(_ result: AIResult) {
        let name = result.action.rawValue
        guard !result.isError else { return Announcer.announce("\(name) failed. \(result.result)") }
        if let progress = result.progress {
            if let failure = progress
                .failure { return Announcer.announce("\(name): part could not be summarized. \(failure)") }
            guard let latest = progress.answers.last, !progress.isReading, !progress.isCombining else {
                return Announcer.announce("\(name): reading the next part")
            }
            let position = String(localized: "Part \(latest.index) of \(progress.partCount) summarized.")
            return Announcer.announce("\(name). \(position) \(latest.text)")
        }
        let note = result.coverage.flatMap { $0.isPartial ? " " + AIResultTitle.coverageNote($0) : nil } ?? ""
        Announcer.announce("\(name) result: \(result.result)\(note)")
    }
}

/// The shelf's accessibility label stays "Clipboard history"; what a VoiceOver user hears on opening it is that label
/// and how many clips it holds. A locked history says nothing about its contents, not even their number.
@MainActor
enum ShelfAnnouncement {
    static func opened(clipCount: Int, isLocked: Bool) {
        guard !isLocked else { return }
        Announcer.announce(clipCount == 0
            ? String(localized: "Clipboard history, empty")
            : String(localized: "Clipboard history, \(clipCount) clips"))
    }
}

@MainActor
enum SelectionAnnouncement {
    static func announce(count: Int) {
        switch count {
        case 0: Announcer.announce("Selection cleared")
        default: Announcer.announce(String(localized: "\(count) clips selected"))
        }
    }
}

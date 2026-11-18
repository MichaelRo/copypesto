// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The one status line of the Sync screen. Only a completed exchange (`SyncStatus.upToDate`) reads as success; a
/// folder that cannot be used is a repair, whatever the controller last said (ADR 0018).
struct MobileSyncStatus: Equatable {
    enum Tone: Equatable {
        case good
        case neutral
        case attention
        case problem
    }

    let title: String
    let detail: String
    let tone: Tone
    let needsFolder: Bool

    init(title: String, detail: String, tone: Tone, needsFolder: Bool = false) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.needsFolder = needsFolder
    }

    init(folderProblem: SyncFolderProblem?, isEnabled: Bool, status: SyncStatus?, device: SyncDeviceKind) {
        if let folderProblem {
            self = Self.repair(Self.detail(for: folderProblem))
        } else if !isEnabled {
            self.init(title: String(localized: "Off"), detail: SyncCopy.offDetail(device), tone: .neutral)
        } else {
            self = Self.running(status ?? .off)
        }
    }

    private static func repair(_ detail: String) -> MobileSyncStatus {
        MobileSyncStatus(
            title: String(localized: "Choose the folder again"), detail: detail, tone: .problem, needsFolder: true
        )
    }

    private static func detail(for problem: SyncFolderProblem) -> String {
        switch problem {
        case .stale: String(localized: "The link to the sync folder is out of date.")
        case .unresolvable: String(localized: "Pesto can no longer find the sync folder.")
        case .unreachable: String(localized: "Pesto cannot open the sync folder.")
        }
    }

    private static func running(_ status: SyncStatus) -> MobileSyncStatus {
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        return switch status {
        case .off:
            MobileSyncStatus(
                title: String(localized: "Checking the folder"),
                detail: String(localized: "The first exchange has not finished yet."), tone: .neutral
            )
        case .paused:
            MobileSyncStatus(
                title: String(localized: "Paused"),
                detail: String(localized: "Sync resumes when your history is unlocked."), tone: .attention
            )
        case let .upToDate(date):
            MobileSyncStatus(
                title: String(localized: "Up to date"), detail: String(localized: "Checked at \(time(date))."),
                tone: .good
            )
        case let .receiving(done, total):
            MobileSyncStatus(
                title: String(localized: "Receiving"), detail: String(localized: "\(done) of \(total) files."),
                tone: .neutral
            )
        case .waitingForFolder:
            MobileSyncStatus(
                title: String(localized: "Waiting for the folder"),
                detail: String(localized: "Its files have not finished downloading."), tone: .attention
            )
        case .folderMissing:
            repair(String(localized: "The Pesto Sync folder was moved or deleted."))
        case let .nothingNew(since):
            MobileSyncStatus(
                title: String(localized: "Nothing new since \(time(since))"),
                detail: String(localized: "Your other devices may be asleep, or iCloud Drive is paused."),
                tone: .attention
            )
        case .needsKey:
            MobileSyncStatus(
                title: String(localized: "New key needed"),
                detail: String(localized: "Sync was reset on another device. Enter its new recovery key."),
                tone: .attention
            )
        case let .refused(reason):
            MobileSyncStatus(title: String(localized: "Refused"), detail: reason, tone: .problem)
        }
    }
}

// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

extension SyncStatus {
    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    var title: String {
        switch self {
        case .off: "Sync is off"
        case .paused: "Paused"
        case .upToDate: "Up to date"
        case .receiving: "Receiving from your other Macs"
        case .waitingForFolder: "Waiting for the Folder"
        case .folderMissing: "Folder Missing"
        case let .nothingNew(since): "Nothing New Since \(time(since))"
        case .needsKey: "New key needed"
        case .refused: "Refused"
        }
    }

    var detail: String {
        switch self {
        case .off: SyncCopy.offDetail
        case .paused: String(localized: "Your history is locked. Sync resumes when you unlock it.")
        case let .upToDate(date): String(localized: "Checked at \(time(date)).")
        case let .receiving(done, total): String(localized: "\(done) of \(total) files. The shelf stays usable.")
        case .waitingForFolder: String(localized: "iCloud Drive has not finished downloading it.")
        case .folderMissing: String(localized: "The Pesto Sync folder was moved or deleted.")
        case .nothingNew: String(localized: "Your other Macs may be asleep, or iCloud Drive is paused.")
        case .needsKey: String(localized: "Sync was reset on another Mac. Enter its new recovery key.")
        case let .refused(reason): reason
        }
    }

    var dotColor: Color {
        switch self {
        case .upToDate, .receiving: .statusGood
        case .refused, .folderMissing: .statusBad
        case .waitingForFolder, .nothingNew, .needsKey, .paused: .statusWarning
        case .off: .secondary
        }
    }

    var chipText: String {
        switch self {
        case .off: String(localized: "Sync: Off")
        case .upToDate: String(localized: "Sync: Up to date")
        case .receiving: String(localized: "Sync: Receiving")
        case .paused: String(localized: "Sync: Paused")
        case .refused: String(localized: "Sync: Refused")
        default: String(localized: "Sync: Needs You")
        }
    }
}

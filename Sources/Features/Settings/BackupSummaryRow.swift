// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The first thing in the Backup group: where the clips are, and what the backup is doing, in one line.
struct BackupSummaryRow: View {
    let chip: BackupChip
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Text("Your clips stay on this Mac.").font(.headline)
            Spacer(minLength: 12)
            HStack(spacing: 7) {
                Circle().fill(chip.dotColor).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(chip.summaryText(now: now)).font(.callout)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your clips stay on this Mac. \(chip.summaryText(now: now)).")
        .accessibilityIdentifier(AccessibilityID.backupStatus)
    }
}

/// What the backup last did, under its switch: a dot and one sentence, then when the next run is due.
struct BackupStatusLine: View {
    let chip: BackupChip
    let lastBytes: Int
    let lastMessage: String?
    let pulse: Int
    let automatic: Bool
    let nextText: String?
    @State private var pulsing = false

    private var detail: String {
        switch chip {
        case .off: ""
        case .waiting: String(localized: "No backup has been written yet. It updates by itself after you copy.")
        case let .upToDate(date):
            String(
                localized: "Up to date. \(BackupMessages.size(lastBytes)), saved \(BackupStatus.lastBackupText(date))."
            )
        case .paused:
            String(localized: """
            You cleared everything and kept the backup, so it still holds your old clips. \
            Automatic backup waits until you choose.
            """)
        case let .needsYou(problem): lastMessage ?? problem.explanation
        }
    }

    private var schedule: String? {
        guard case .upToDate = chip else { return nil }
        if !automatic { return String(localized: "Only when you choose Back Up Now.") }
        return nextText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(chip.dotColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulsing ? 1.5 : 1)
                    .accessibilityHidden(true)
                Text(detail).font(.callout)
            }
            if let schedule { Text(schedule).pestoCaption().padding(.leading, 16) }
        }
        .padding(.top, 2)
        .onChange(of: pulse) { _, _ in
            withAnimation(Motion.animation(.pestoPop)) { pulsing = true }
            Task {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(Motion.animation(.pestoWash)) { pulsing = false }
            }
        }
    }
}

extension BackupChip {
    var tileTint: Color? {
        switch self {
        case .upToDate: .statusGood
        case .needsYou: .statusBad
        case .off, .waiting, .paused: nil
        }
    }

    var dotColor: Color {
        switch self {
        case .upToDate: .statusGood
        case .needsYou: .statusBad
        case .waiting, .paused, .off: .secondary
        }
    }
}

extension BackupProblem {
    var explanation: String {
        switch self {
        case .folderMissing: String(localized: "The folder is not available. Is the drive or iCloud Drive connected?")
        case .failed: String(localized: "The last backup could not be written.")
        case .refused: String(localized: "The last backup was left as it is. Choose Back Up Now to see why.")
        }
    }
}

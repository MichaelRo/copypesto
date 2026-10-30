// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// What the history amounts to, at the top of Data: how many clips, how much disk, how old the oldest is, and when the
/// backup last ran. Counts and sizes only, so it needs no unlock.
struct DataStatStrip: View {
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var snapshot: PrivacySnapshot?
    @State private var bytes: Int?
    @State private var backupTick = 0

    var body: some View {
        SettingsStatStrip(stats: [
            SettingsStat(id: "clips", value: clipsText, label: "Clips"),
            SettingsStat(id: "disk", value: bytes.map(Self.sizeText) ?? "…", label: "On disk"),
            SettingsStat(id: "oldest", value: oldestText, label: "Oldest clip"),
            SettingsStat(
                id: "backup", value: chip.tileValue(), label: LocalizedStringKey(chip.tileLabel),
                tint: chip.tileTint
            )
        ])
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            backupTick += 1
        }
    }

    private var clipsText: String {
        snapshot.map { "\($0.clipCount.formatted())" } ?? "…"
    }

    private var oldestText: String {
        guard let snapshot else { return "…" }
        return snapshot.oldest.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "None"
    }

    private var chip: BackupChip {
        _ = backupTick
        let settings = AutoBackupSettings()
        return BackupChip(
            status: BackupStatus(isEnabled: settings.isEnabled, pausedAfterClear: settings.pausedAfterClear),
            lastBackup: settings.lastBackup, problem: settings.problem
        )
    }

    private static func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func refresh() async {
        snapshot = await appState.privacySnapshot?()
        var descriptor = FetchDescriptor<ClipboardItem>()
        descriptor.propertiesToFetch = [\.byteSize]
        bytes = (try? modelContext.fetch(descriptor))?.reduce(0) { $0 + $1.byteSize } ?? 0
    }
}

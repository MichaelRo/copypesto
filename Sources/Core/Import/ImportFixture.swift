// SPDX-License-Identifier: MIT
import Foundation

/// Libraries made up for a UI test: the import menu opens a file panel, which a test cannot drive, so a UI-test launch
/// can name one of these (`RuntimeConfiguration.importFixture`) and the sheet shows it. The records hold no clip data.
public enum ImportFixture {
    public static func preview(named name: String, now: Date = .now) -> ImportPreview? {
        func record(_ daysAgo: Double, _ pinboard: String? = nil) -> PasteImportRecord {
            PasteImportRecord(
                pinboard: pinboard, title: nil, timestamp: now.addingTimeInterval(-daysAgo * 86_400),
                sourceBundleID: nil, representations: []
            )
        }
        let history = [record(2), record(10), record(400)]
        switch name {
        case "maccy":
            let records = [record(1, "Pinned in Maccy"), record(3, "Pinned in Maccy")] + history
            return ImportPreview(appName: "Maccy", library: ClipboardAppLibrary(records: records, skipped: 1))
        case "alfred":
            return ImportPreview(appName: "Alfred", library: ClipboardAppLibrary(records: history, skipped: 2))
        case "paste":
            let library = PasteLibrary(
                pinboards: [.init(name: "Commands", records: [record(1, "Commands"), record(3, "Commands")])],
                history: history
            )
            return ImportPreview(paste: library)
        default:
            return nil
        }
    }

    /// The file `Other File…` reads in a UI test, where the file panel cannot be driven.
    public static let otherFileName = "clips-export.csv"
    public static let otherFileCSV = Data(
        "Content,Copied at,Pinned\nStandup notes,2026-01-02,no\nhttps://copypesto.net,2026-01-03,yes\n,2026-01-04,no\n"
            .utf8
    )

    /// The names in a fixture value: one app, or several separated by commas.
    public static func names(in value: String?) -> [String] {
        (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The library a fixture value holds for the app called `appName`, if it names that app.
    public static func preview(forApp appName: String, in value: String?, now: Date = .now) -> ImportPreview? {
        names(in: value).lazy.compactMap { preview(named: $0, now: now) }.first { $0.appName == appName }
    }

    /// The fixture a UI-test launch asked for, or nil in every other launch.
    public static var requested: String? {
        let configuration = RuntimeConfiguration.current
        return configuration.mode == .uiTest ? configuration.importFixture : nil
    }
}

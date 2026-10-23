// SPDX-License-Identifier: MIT
import XCTest

final class FileClipCardTests: PestoUITestCase {
    private func fileCardLabels() -> [String] {
        cards.matching(NSPredicate(format: "label BEGINSWITH 'file'")).allElementsBoundByIndex.map(\.label)
    }

    func test_fileCards_areNamedByFileNotByRawPath() {
        launch(seed: "files")
        showOverlay()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))

        let labels = fileCardLabels()
        XCTAssertEqual(labels.count, 3, "\(labels)")
        XCTAssertTrue(labels.contains { $0.contains("hosts in etc") && !$0.contains("moved") }, "\(labels)")
        XCTAssertTrue(labels.contains { $0.contains("basil-harvest-notes.pdf in Documents, moved or deleted") })
        XCTAssertTrue(labels.contains { $0.contains("2 files: hosts, pine-nut-inventory.csv, 1 moved or deleted") })
        XCTAssertFalse(labels.contains { $0.contains("file://") }, "a raw path is still exposed")
        capture("file-cards")
    }
}

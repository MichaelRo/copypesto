// SPDX-License-Identifier: MIT
import Foundation

struct StagedUpdate {
    static let releasesPage = URL(string: "https://copypesto.net/releases/")

    let version: String
    let whatsNew: URL?
    let install: () -> Void

    init(version: String, fullNotes: URL?, itemNotes: URL?, install: @escaping () -> Void) {
        self.version = version
        whatsNew = fullNotes ?? itemNotes ?? Self.releasesPage
        self.install = install
    }
}

// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Sync never reaches the network by itself")
struct SyncNetworkScanTests {
    private static let forbidden = [
        "URLSession", "URLRequest", "NWConnection", "NWListener", "CFSocket", "import Network", "CloudKit",
        "CKContainer",
        "WebSocket", "NSURLConnection"
    ]

    @Test("no networking API appears in the sync folders: the folder's own provider is the only transport")
    func noNetworkingInSync() throws {
        var files = try SourceTree.swiftFiles(in: "Core/Sync", minimum: 8)
        files += (try? SourceTree.swiftFiles(in: "Core/Storage/Sync", minimum: 0)) ?? []
        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in Self.forbidden where text.contains(needle) {
                offenders.append("\(SourceTree.relativePath(file)): \(needle)")
            }
        }
        #expect(offenders.isEmpty, "\(offenders.sorted())")
    }
}

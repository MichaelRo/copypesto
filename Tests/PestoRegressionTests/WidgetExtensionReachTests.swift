// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// PestoCore is linked into the Mac's Controls extension in every build (ADR 0059), and the iOS widget links it too.
/// The
/// widget opens only its sealed snapshot with its own key: no code in the extensions may reach the history key, the
/// store, or the network.
@Suite("The widget extensions reach no history key, no store and no network")
struct WidgetExtensionReachTests {
    private static let forbidden = [
        #"\bBlobEncryption\b"#, #"\bKeychainSecretStore\b"#, #"\bloadOrCreateKey\b"#, #"\bblobKeyAccount\b"#,
        #"\bModelContainer\b"#, #"\bModelContext\b"#, #"\bStorageService\b"#, #"\bModelContainerSetup\b"#,
        #"\bURLMetadataFetcher\b"#, #"\bLinkPreviewLoader\b"#, #"\bRemoteGIFFetcher\b"#, #"\bURLSession\b"#,
        #"\bLPMetadataProvider\b"#, #"\bNWConnection\b"#, #"\bSyncController\b"#
    ]

    @Test("Sources/Widget, Sources/Controls and Sources/MobileWidget name none of them")
    func extensionsReachOnlyTheirSnapshot() throws {
        let files = try SourceTree.swiftFiles(in: "Widget", minimum: 10)
            + SourceTree.swiftFiles(in: "Controls", minimum: 1)
            + SourceTree.swiftFiles(in: "MobileWidget", minimum: 2)
        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for pattern in Self.forbidden where text.range(of: pattern, options: .regularExpression) != nil {
                offenders.append("\(SourceTree.relativePath(file)) names \(pattern)")
            }
        }
        #expect(offenders.isEmpty, "\(offenders.joined(separator: "\n"))")
    }

    @Test("the scan sees a name it forbids")
    func patternsMatch() {
        let sample = "let key = try BlobEncryption().loadOrCreateKey(); URLSession.shared"
        let hits = Self.forbidden.filter { sample.range(of: $0, options: .regularExpression) != nil }
        #expect(hits.count == 3)
        #expect(
            "SharedKeychainSecretStore(accessGroup: g)".range(of: Self.forbidden[1], options: .regularExpression)
                == nil,
            "the widget's own Keychain group store is allowed"
        )
    }
}

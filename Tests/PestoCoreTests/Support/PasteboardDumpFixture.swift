// SPDX-License-Identifier: MIT
import AppKit
import Foundation
@testable import PestoCore

struct PasteboardDumpFixture: Decodable {
    struct Flavor: Decodable {
        let utf8: String?
        let base64: String?

        var data: Data? {
            if let utf8 { return Data(utf8.utf8) }
            if let base64 { return Data(base64Encoded: base64) }
            return nil
        }
    }

    let sourceBundleID: String
    let flavors: [String: Flavor]

    static func load(named filename: String) throws -> Self {
        let url = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/PasteboardDumps/\(filename)")
        let raw = try Data(contentsOf: url)
        return try JSONDecoder().decode(Self.self, from: raw)
    }

    func write(to board: FakePasteboard, extraTypes: [String] = []) {
        var types: [NSPasteboard.PasteboardType] = []
        var dataMap: [NSPasteboard.PasteboardType: Data] = [:]
        var stringMap: [NSPasteboard.PasteboardType: String] = [:]
        for (uti, flavor) in flavors {
            let pbType = NSPasteboard.PasteboardType(uti)
            types.append(pbType)
            if let data = flavor.data {
                dataMap[pbType] = data
            }
            if let utf8 = flavor.utf8 {
                stringMap[pbType] = utf8
            }
        }
        for extra in extraTypes {
            types.append(NSPasteboard.PasteboardType(extra))
        }
        board.write(types: types, data: dataMap, strings: stringMap)
    }
}

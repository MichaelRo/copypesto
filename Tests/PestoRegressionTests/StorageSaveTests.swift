// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("The storage actor's saves roll back on failure")
struct StorageSaveTests {
    @Test("StorageService saves through saveOrRollback, never straight, so a failed save leaves nothing pending")
    func storageServiceNeverSavesDirectly() throws {
        let files = try SourceTree.files(in: "Core/Storage/Models", minimum: 20)
            .filter { $0.lastPathComponent.hasPrefix("StorageService") }
        #expect(files.count >= 10, "the scan found only \(files.count) StorageService files")

        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let direct = text.components(separatedBy: "\n").enumerated().filter { _, line in
                line.contains("modelContext.save()") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            }
            let allowed = file.lastPathComponent == "StorageService+Saving.swift" ? 1 : 0
            if direct.count > allowed {
                offenders
                    .append("\(file.lastPathComponent):\(direct.map { String($0.offset + 1) }.joined(separator: ","))")
            }
        }
        #expect(offenders.isEmpty, "call saveOrRollback() instead: \(offenders.joined(separator: "; "))")
    }

    @Test("no file under Sources saves a SwiftData context directly: one save policy, the one that rolls back")
    func nothingSavesDirectly() throws {
        let files = try SourceTree.allSwiftFiles(in: SourceTree.minimumFileCounts)
        var offenders: [String] = []
        for file in files where file.lastPathComponent != "ModelContext+SaveOrRollback.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if !code.hasPrefix("//"), code.range(of: #"[cC]ontext\.save\(\)"#, options: .regularExpression) != nil {
                    offenders.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "call saveOrRollback() instead: \(offenders.joined(separator: ", "))")
    }
}

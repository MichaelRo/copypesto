// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import Testing
@testable import PestoCore

/// ADR 0017's performance gate for noticing look-alike clips: what a signature costs at ingest, what the index holds,
/// what a lookup costs, and whether it finds the families it should. It measures on a developer Mac and only emits on
/// CI (`isCI`). Run it optimized: `swift test -Xswiftc -O --filter SimilarityPerformance`.
@Suite("Similarity performance")
struct SimilarityPerformanceTests {
    private struct Generator {
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        mutating func next() -> Int {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Int(truncatingIfNeeded: state >> 1)
        }

        mutating func pick(_ count: Int) -> Int {
            next() % count
        }
    }

    private static let vocabulary: [String] = (0..<900).map { "w\(String($0, radix: 36))x" + String(repeating: "e", count: $0 % 4) }
    private static let names = (0..<300).map { "Name\(String($0, radix: 36))" }

    private func prose(_ generator: inout Generator, words: Int) -> String {
        (0..<words).map { _ in Self.vocabulary[generator.pick(Self.vocabulary.count)] }.joined(separator: " ")
    }

    private func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }

    private func report(_ line: String) {
        FileHandle.standardError.write(Data("PERF similarity \(line)\n".utf8))
    }

    @Test("signature, index and lookup cost on 5,000 clips, and how many families are found")
    func whenFiveThousandClips_thenCostAndAccuracyMeasured() {
        var generator = Generator()
        var texts: [(id: UUID, text: String, family: Int?)] = []
        let familyShapes = [(words: 12, count: 10), (words: 35, count: 10), (words: 150, count: 10), (words: 400, count: 10)]
        var familyNumber = 0
        for shape in familyShapes {
            for _ in 0..<10 {
                let body = (0..<shape.words).map { _ in Self.vocabulary[generator.pick(Self.vocabulary.count)] }
                for _ in 0..<shape.count {
                    var words = body
                    words[1] = Self.names[generator.pick(Self.names.count)]
                    words[shape.words / 2] = Self.names[generator.pick(Self.names.count)]
                    texts.append((UUID(), words.joined(separator: " "), familyNumber))
                }
                familyNumber += 1
            }
        }
        while texts.count < 5000 {
            texts.append((UUID(), prose(&generator, words: 8 + generator.pick(300)), nil))
        }
        var shuffler = SeededShuffle(seed: 7)
        texts.shuffle(using: &shuffler)

        let clock = ContinuousClock()
        let footprintBefore = footprintBytes()

        var signatures: [TextSignature?] = []
        let signatureTime = clock.measure { signatures = texts.map { TextSignature.make(from: $0.text) } }
        let perSignatureMicros = Double(signatureTime.components.attoseconds) / 1e12 / Double(texts.count)

        var index = SimilarityIndex()
        let buildTime = clock.measure {
            for (offset, text) in texts.enumerated() {
                if let signature = signatures[offset] { index.insert(signature, for: text.id) }
            }
        }

        var found = 0
        var expected = 0
        var correct = 0
        var returned = 0
        var lookups = 0
        var foundByShape = [Int](repeating: 0, count: familyShapes.count)
        var expectedByShape = [Int](repeating: 0, count: familyShapes.count)
        var lookupNanos: Double = 0
        let familyByID = Dictionary(uniqueKeysWithValues: texts.map { ($0.id, $0.family) })
        var members: [Int: [UUID]] = [:]
        for text in texts { if let family = text.family { members[family, default: []].append(text.id) } }
        for (offset, text) in texts.enumerated() {
            guard let family = text.family, let signature = signatures[offset] else { continue }
            let start = clock.now
            let matches = index.matches(for: signature, excluding: text.id)
            let elapsed = clock.now - start
            lookupNanos += Double(elapsed.components.attoseconds) / 1e9
            lookups += 1
            let sameFamily = matches.filter { familyByID[$0.id] ?? nil == family }
            found += sameFamily.count
            foundByShape[family / 10] += sameFamily.count
            expectedByShape[family / 10] += (members[family]?.count ?? 1) - 1
            expected += (members[family]?.count ?? 1) - 1
            correct += sameFamily.count
            returned += matches.count
        }
        let footprintAfter = footprintBytes()

        report("signature \(String(format: "%.1f", perSignatureMicros)) us each over \(texts.count) clips")
        report("index build \(String(format: "%.1f", Double(buildTime.components.attoseconds) / 1e15)) ms for \(index.count) signatures")
        report("lookup \(String(format: "%.1f", lookupNanos / Double(max(1, lookups)) / 1000)) us average over \(lookups) queries")
        report("index approx \(index.approximateBytes / 1024) KB, footprint change \((footprintAfter - footprintBefore) / 1024) KB")
        report("recall \(String(format: "%.3f", Double(found) / Double(max(1, expected)))) precision \(String(format: "%.3f", Double(correct) / Double(max(1, returned))))")

        for (shapeIndex, shape) in familyShapes.enumerated() {
            let recall = Double(foundByShape[shapeIndex]) / Double(max(1, expectedByShape[shapeIndex]))
            report("recall at \(shape.words) words: \(String(format: "%.3f", recall))")
        }

        let lookupBudgetMilliseconds = isCI ? 1.0 : 4.0
        #expect(lookupNanos / Double(max(1, lookups)) / 1e6 < lookupBudgetMilliseconds)
        #expect(Double(correct) / Double(max(1, returned)) > 0.95)
    }
}

private struct SeededShuffle: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

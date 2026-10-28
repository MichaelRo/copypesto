// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import Testing
@testable import PestoCore

/// ADR 0017's performance gate for noticing look-alike clips: what a signature costs at ingest, what the index holds,
/// what a lookup costs, and whether it finds the families it should. It measures on a developer Mac and only emits on
/// CI (the `CI` variable). Run it optimized: `swift test -Xswiftc -O --filter SimilarityPerformance`.
@Suite("Similarity performance")
struct SimilarityPerformanceTests {
    private struct Clip {
        let id = UUID()
        let text: String
        let family: Int?
    }

    private struct Shape {
        let words: Int
        let count: Int
    }

    private struct Generator: RandomNumberGenerator {
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    private static let shapes = [
        Shape(words: 12, count: 10),
        Shape(words: 35, count: 10),
        Shape(words: 150, count: 10),
        Shape(words: 400, count: 10)
    ]
    private static let vocabulary = (0..<900)
        .map { "w\(String($0, radix: 36))x" + String(repeating: "e", count: $0 % 4) }
    private static let names = (0..<300).map { "Name\(String($0, radix: 36))" }

    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }

    private func clips() -> [Clip] {
        var generator = Generator()
        var result: [Clip] = []
        var family = 0
        for shape in Self.shapes {
            for _ in 0..<10 {
                let body = (0..<shape.words).map { _ in Self.vocabulary.randomElement(using: &generator) ?? "" }
                for _ in 0..<shape.count {
                    var words = body
                    words[1] = Self.names.randomElement(using: &generator) ?? ""
                    words[shape.words / 2] = Self.names.randomElement(using: &generator) ?? ""
                    result.append(Clip(text: words.joined(separator: " "), family: family))
                }
                family += 1
            }
        }
        while result.count < 5000 {
            let count = 8 + Int.random(in: 0..<300, using: &generator)
            let words = (0..<count).map { _ in Self.vocabulary.randomElement(using: &generator) ?? "" }
            result.append(Clip(text: words.joined(separator: " "), family: nil))
        }
        result.shuffle(using: &generator)
        return result
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

    private func report(_ line: String) {
        FileHandle.standardError.write(Data("PERF similarity \(line)\n".utf8))
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test("signature, index and lookup cost on 5,000 clips, and how many families are found")
    func whenFiveThousandClips_thenCostAndAccuracyMeasured() {
        let clips = clips()
        let clock = ContinuousClock()
        let footprintBefore = footprintBytes()

        var signatures: [TextSignature?] = []
        let signingTime = clock.measure { signatures = clips.map { TextSignature.make(from: $0.text) } }
        var index = SimilarityIndex()
        let buildTime = clock.measure {
            for (clip, signature) in zip(clips, signatures) {
                if let signature { index.insert(signature, for: clip.id) }
            }
        }

        let members = Dictionary(grouping: clips.filter { $0.family != nil }, by: { $0.family ?? 0 })
        let familyByID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0.family) })
        var found = [Int](repeating: 0, count: Self.shapes.count)
        var expected = found
        var returned = 0
        var lookups = 0
        var lookupMilliseconds = 0.0
        for (clip, signature) in zip(clips, signatures) {
            guard let family = clip.family, let signature else { continue }
            let start = clock.now
            let matches = index.matches(for: signature, excluding: clip.id)
            lookupMilliseconds += milliseconds(clock.now - start)
            lookups += 1
            returned += matches.count
            found[family / 10] += matches.count(where: { familyByID[$0.id] == family })
            expected[family / 10] += (members[family]?.count ?? 1) - 1
        }
        let precision = Double(found.reduce(0, +)) / Double(max(1, returned))
        let averageLookup = lookupMilliseconds / Double(max(1, lookups))

        report("signature \(String(format: "%.1f", milliseconds(signingTime) * 1000 / Double(clips.count))) us each")
        report("index build \(String(format: "%.1f", milliseconds(buildTime))) ms for \(index.count) signatures")
        report("lookup \(String(format: "%.1f", averageLookup * 1000)) us average over \(lookups) queries")
        let footprintChange = (footprintBytes() - footprintBefore) / 1024
        report("index approx \(index.approximateBytes / 1024) KB, footprint change \(footprintChange) KB")
        report("precision \(String(format: "%.3f", precision))")
        for (shape, pair) in zip(Self.shapes, zip(found, expected)) {
            report("recall at \(shape.words) words: \(String(format: "%.3f", Double(pair.0) / Double(max(1, pair.1))))")
        }

        #expect(averageLookup < (isCI ? 1.0 : 4.0))
        #expect(precision > 0.95)
    }
}

// SPDX-License-Identifier: MIT
import Foundation

/// Numbers from the hardware tests go to stderr (the `xcodebuild` log keeps them) with a prefix `grep PERF` finds.
enum PerfReport {
    struct Timing {
        let median: Double
        let min: Double
        let max: Double

        var text: String {
            String(format: "median %.2f ms (min %.2f, max %.2f)", median, min, max)
        }
    }

    static func emit(_ line: String) {
        FileHandle.standardError.write(Data("PERF \(line)\n".utf8))
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Runs `body` `runs` times and returns the median, minimum and maximum in milliseconds.
    static func time(runs: Int = 7, _ body: () throws -> Void) rethrows -> Timing {
        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<runs {
            let start = clock.now
            try body()
            samples.append(milliseconds(clock.now - start))
        }
        return timing(of: samples)
    }

    static func timing(of samples: [Double]) -> Timing {
        let sorted = samples.sorted()
        return Timing(median: sorted[sorted.count / 2], min: sorted[0], max: sorted[sorted.count - 1])
    }
}

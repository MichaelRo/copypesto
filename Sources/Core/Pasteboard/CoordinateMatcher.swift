// SPDX-License-Identifier: MIT
import Foundation

/// Finds latitude and longitude pairs in a short text. Every pattern is bounded (no group repeats), the caller scans
/// the
/// preview only, and a pair is offered only when both numbers are possible coordinates: a wrong guess costs one menu
/// line.
enum CoordinateMatcher {
    struct Pair: Equatable {
        let latitude: Double
        let longitude: Double
    }

    private static let notPartOfNumber = #"(?<![0-9.\-])"#
    private static let latitude2 = #"([-+]?(?:[1-8]?\d\.\d{2,}|90(?:\.0+)?))"#
    private static let longitude2 = #"([-+]?(?:180(?:\.0+)?|(?:1[0-7]\d|\d{1,2})\.\d{2,}))"#
    private static let latitude4 = #"([-+]?(?:[1-8]?\d\.\d{4,}|90(?:\.0+)?))"#
    private static let longitude4 = #"([-+]?(?:180(?:\.0+)?|(?:1[0-7]\d|\d{1,2})\.\d{4,}))"#
    private static let tail = #"(?![0-9.\-])"#
    private static let minuteMark = #"['′’]"#
    private static let secondMark = #"["″”]"#

    /// Two decimals are enough beside a comma or semicolon; beside a space only four are (`1.2.3.4` is a version).
    private static let decimalPatterns = [
        notPartOfNumber + latitude2 + #"\s*[,;]\s*"# + longitude2 + tail,
        notPartOfNumber + latitude4 + #"[ \t]+"# + longitude4 + tail
    ]
    private static let directional =
        notPartOfNumber + #"(\d{1,2}(?:\.\d+)?)\s*°?\s*([NS])[\s,;]*(\d{1,3}(?:\.\d+)?)\s*°?\s*([EW])\b"#
    private static let dms =
        notPartOfNumber + #"(\d{1,2})\s*°\s*(\d{1,2})\s*"# + minuteMark + #"\s*(\d{1,2}(?:\.\d+)?)\s*"#
            + secondMark + #"?\s*([NS])[\s,;]*(\d{1,3})\s*°\s*(\d{1,2})\s*"# + minuteMark
            + #"\s*(\d{1,2}(?:\.\d+)?)\s*"# + secondMark + #"?\s*([EW])\b"#

    static func pairs(in text: String, regex: (String) -> NSRegularExpression?) -> [Pair] {
        var found: [Pair] = []
        let range = NSRange(text.startIndex..., in: text)
        func groups(_ match: NSTextCheckingResult) -> [String] {
            (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        }
        func add(_ latitude: Double, _ longitude: Double) {
            guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return }
            found.append(Pair(latitude: latitude, longitude: longitude))
        }
        for pattern in decimalPatterns {
            for match in regex(pattern)?.matches(in: text, range: range) ?? [] {
                let parts = groups(match).compactMap(Double.init)
                if parts.count == 2 { add(parts[0], parts[1]) }
            }
        }
        for match in regex(directional)?.matches(in: text, range: range) ?? [] {
            let parts = groups(match)
            guard parts.count == 4, let lat = Double(parts[0]), let lon = Double(parts[2]) else { continue }
            add(parts[1].uppercased() == "S" ? -lat : lat, parts[3].uppercased() == "W" ? -lon : lon)
        }
        for match in regex(dms)?.matches(in: text, range: range) ?? [] {
            let parts = groups(match)
            guard parts.count == 8,
                  let lat = degrees(parts[0], parts[1], parts[2]),
                  let lon = degrees(parts[4], parts[5], parts[6]) else { continue }
            add(parts[3].uppercased() == "S" ? -lat : lat, parts[7].uppercased() == "W" ? -lon : lon)
        }
        return found
    }

    /// Degrees, minutes and seconds as decimal degrees; minutes and seconds under 60.
    private static func degrees(_ degrees: String, _ minutes: String, _ seconds: String) -> Double? {
        guard let whole = Double(degrees), let mins = Double(minutes), let secs = Double(seconds), mins < 60,
              secs < 60 else
        {
            return nil
        }
        return whole + mins / 60 + secs / 3600
    }
}

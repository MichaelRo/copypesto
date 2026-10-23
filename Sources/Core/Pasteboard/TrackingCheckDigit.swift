// SPDX-License-Identifier: MIT

/// The check digits the carriers put at the end of a tracking number. A random run of digits passes one time in ten, so
/// a
/// pass is never enough to call a bare run a parcel (`EntityDetector` also wants the carrier's name there); a failure
/// is a
/// typo or not a tracking number at all.
public enum TrackingCheckDigit {
    /// `1Z`, 15 characters of shipper, service and package, then the check digit. Letters count as `(code - 63) mod
    /// 10`.
    public static func isValidUPS(_ number: String) -> Bool {
        let chars = Array(number.uppercased())
        guard chars.count == 18, chars[0] == "1", chars[1] == "Z", let check = digit(chars[17]) else { return false }
        var sum = 0
        for (index, char) in chars[2..<17].enumerated() {
            let value: Int
            if let number = digit(char) {
                value = number
            } else if let ascii = char.asciiValue, (65...90).contains(ascii) {
                value = (Int(ascii) - 63) % 10
            } else {
                return false
            }
            sum += value * (index.isMultiple(of: 2) ? 1 : 2)
        }
        return (10 - sum % 10) % 10 == check
    }

    /// 20 or 22 digits, weights 3, 1, 3, 1 from the left over all but the last. A 20-digit number may also be the
    /// legacy
    /// format, whose check is made on the number with `91` in front of it (the published definition).
    public static func isValidUSPS(_ number: String) -> Bool {
        guard let digits = digits(of: number, counts: [20, 22]) else { return false }
        if mod10(digits, evenWeight: 3, oddWeight: 1) { return true }
        return digits.count == 20 && mod10([9, 1] + digits, evenWeight: 3, oddWeight: 1)
    }

    /// 12 digits: weights 3, 1, 7 over the first 11, `sum mod 11 mod 10`.
    public static func isValidFedExExpress(_ number: String) -> Bool {
        guard let digits = digits(of: number, counts: [12]) else { return false }
        let weights = [3, 1, 7, 3, 1, 7, 3, 1, 7, 3, 1]
        let sum = zip(digits.dropLast(), weights).reduce(0) { $0 + $1.0 * $1.1 }
        return sum % 11 % 10 == digits[11]
    }

    /// 15 digits: weights 1, 3, 1, 3 over the first 14.
    public static func isValidFedExGround(_ number: String) -> Bool {
        guard let digits = digits(of: number, counts: [15]) else { return false }
        return mod10(digits, evenWeight: 1, oddWeight: 3)
    }

    /// 10 or 11 digits: the number before the last digit, `mod 7`, is the last digit.
    public static func isValidDHL(_ number: String) -> Bool {
        guard let digits = digits(of: number, counts: [10, 11]) else { return false }
        let body = digits.dropLast().reduce(0) { ($0 * 10 + $1) % 7 }
        return body == digits[digits.count - 1]
    }

    private static func mod10(_ digits: [Int], evenWeight: Int, oddWeight: Int) -> Bool {
        let sum = digits.dropLast().enumerated().reduce(0) { total, item in
            total + item.element * (item.offset.isMultiple(of: 2) ? evenWeight : oddWeight)
        }
        return (10 - sum % 10) % 10 == digits[digits.count - 1]
    }

    private static func digit(_ char: Character) -> Int? {
        guard let ascii = char.asciiValue, (48...57).contains(ascii) else { return nil }
        return Int(ascii) - 48
    }

    private static func digits(of number: String, counts: Set<Int>) -> [Int]? {
        let values = number.map(digit)
        guard counts.contains(values.count), !values.contains(nil) else { return nil }
        return values.compactMap(\.self)
    }
}

// SPDX-License-Identifier: MIT
import Foundation

/// Detects actionable entities (phone numbers, email addresses, street addresses) in plain text.
/// Detection runs at display time from `previewText` — results are never stored to the schema.
public struct EntityDetector: Sendable {
    public enum Entity: Sendable, Equatable {
        case phoneNumber(String)
        case email(String)
        case address(String)
        case coordinates(latitude: Double, longitude: Double)
        case date(EventDetails)
        case trackingNumber(Carrier, String)
        case link(URL)

        public var actionURL: URL? {
            switch self {
            case let .phoneNumber(raw):
                let digits = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                let prefix = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : ""
                return URL(string: "tel://\(prefix)\(digits)")
            case let .email(raw):
                return URL(string: "mailto:\(raw)")
            case let .address(raw):
                let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
                return URL(string: "https://maps.apple.com/?address=\(encoded)")
            case let .coordinates(lat, lon):
                return URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(lat),\(lon)")
            case .date:
                return nil
            case let .trackingNumber(carrier, number):
                return carrier.trackingURL(for: number)
            case let .link(url):
                return url
            }
        }

        public var actionLabel: String {
            switch self {
            case .phoneNumber: "Call"
            case .email: "Compose Email"
            case .address, .coordinates: "Open in Maps"
            case .date: "Add to Calendar"
            case let .trackingNumber(carrier, _): "Track with \(carrier.displayName)"
            case .link: "Open Link"
            }
        }

        public var symbolName: String {
            switch self {
            case .phoneNumber: "phone"
            case .email: "envelope"
            case .address: "map"
            case .coordinates: "location"
            case .date: "calendar.badge.plus"
            case .trackingNumber: "shippingbox"
            case .link: "safari"
            }
        }
    }

    public struct EventDetails: Sendable, Equatable {
        public let title: String
        public let start: Date
        public let hasTime: Bool

        public init(title: String, start: Date, hasTime: Bool) {
            self.title = title
            self.start = start
            self.hasTime = hasTime
        }
    }

    public enum Carrier: Sendable, Equatable {
        case ups, usps, fedex, dhl

        public var displayName: String {
            switch self {
            case .ups: "UPS"
            case .usps: "USPS"
            case .fedex: "FedEx"
            case .dhl: "DHL"
            }
        }

        /// The carrier's own tracking page, opened in the user's browser: Pesto does not fetch it.
        func trackingURL(for number: String) -> URL? {
            switch self {
            case .ups: URL(string: "https://www.ups.com/track?tracknum=\(number)")
            case .usps: URL(string: "https://tools.usps.com/go/TrackConfirmAction?tLabels=\(number)")
            case .fedex: URL(string: "https://www.fedex.com/fedextrack/?trknbr=\(number)")
            case .dhl: URL(string: "https://www.dhl.com/global-en/home/tracking.html?tracking-id=\(number)")
            }
        }
    }

    /// Text longer than this is a document, not a note about an event, so it is not scanned for dates.
    static let maxDateScanLength = 400

    public static func detect(in text: String) -> [Entity] {
        var results: [Entity] = []
        // Phones before emails so a number embedded in an address-like string scores first.
        results += matchPhones(in: text)
        results += matchEmails(in: text)
        results += matchAddresses(in: text)
        results += matchCoordinates(in: text)
        results += matchDates(in: text)
        results += matchTrackingNumbers(in: text)
        results += matchLinks(in: text)
        // A ten-digit tracking number is also a dialable shape; with a carrier's page on offer it is not a phone.
        let trackedDigits = Set(results.compactMap { entity -> String? in
            if case let .trackingNumber(_, number) = entity { number } else { nil }
        })
        results.removeAll { entity in
            if case let .phoneNumber(raw) = entity { trackedDigits.contains(raw.filter(\.isNumber)) } else { false }
        }
        // Dedupe by value — same string appearing multiple times is only one action.
        var seen = Set<String>()
        return results.filter { entity in
            let key = switch entity {
            case let .phoneNumber(s): "phone:\(s)"
            case let .email(s): "email:\(s)"
            case let .address(s): "addr:\(s)"
            case let .coordinates(lat, lon): "coord:\(lat),\(lon)"
            case let .date(details): "date:\(details.start.timeIntervalSince1970)"
            case let .trackingNumber(_, number): "track:\(number)"
            case let .link(url): "link:\(url.absoluteString)"
            }
            return seen.insert(key).inserted
        }
    }

    // MARK: - Pattern matching

    private static func matchPhones(in text: String) -> [Entity] {
        // US + E.164 international formats: (555) 123-4567, 555.123.4567, +1 555 123 4567, +44 20 7946 0958, etc.
        // NANP shape: area code and exchange start 2 to 9 and the area code is not N11. The leading boundary keeps the
        // last ten digits of a longer run (an order or tracking number) from being read as a phone number.
        let usPattern = #"(?<![\w+])(?:\+?1[\s.\-]?)?\(?[2-9](?!11)\d{2}\)?[\s.\-]?[2-9]\d{2}[\s.\-]?\d{4}\b"#
        let intlPattern = #"\+(?:[1-9]\d{0,2})[\s.\-]?(?:\(?\d{1,4}\)?[\s.\-]?){1,4}\d{2,4}\b"#
        var rawMatches = matches(of: usPattern, in: text)
        for match in matches(of: intlPattern, in: text) {
            let digits = match.filter(\.isNumber)
            if digits.count >= 7, digits.count <= 15, !rawMatches.contains(match) {
                rawMatches.append(match)
            }
        }
        return rawMatches.map { .phoneNumber($0) }
    }

    private static func matchEmails(in text: String) -> [Entity] {
        let pattern = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        return matches(of: pattern, in: text).map { .email($0) }
    }

    private static func matchAddresses(in text: String) -> [Entity] {
        // Heuristic: number + direction/street-type keyword on the same line.
        // Keeps false-positive rate low without a full address parser.
        // swiftlint:disable:next line_length
        let pattern = #"(?m)^\d+\s+(?:[NSEW]\w*\s+)?\w+(?:\s+(?:St|Ave|Blvd|Rd|Dr|Ln|Ct|Way|Pl|Terr?|Pkwy|Hwy|Fwy)\.?)\b.*$"#
        return matches(of: pattern, in: text).map { .address($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func matchCoordinates(in text: String) -> [Entity] {
        CoordinateMatcher.pairs(in: text, regex: compiledRegex).map {
            .coordinates(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private static func matchDates(in text: String) -> [Entity] {
        guard text.count <= maxDateScanLength,
              let detector = dateDetector,
              let match = detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).first,
              let date = match.date, let matched = Range(match.range, in: text) else { return [] }
        // A date with no time comes back as noon, so whether the user wrote a time is read from the text itself.
        let phrase = String(text[matched])
        let hasTime = phrase.range(
            of: #"\d{1,2}[:.]\d{2}|\b\d{1,2}\s?(?:am|pm)\b|\bnoon\b|\bmidnight\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        // The whole first line makes the title: the detector's own phrase can swallow real words ("lunch on ...").
        let firstLine = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return [.date(EventDetails(
            title: firstLine.isEmpty ? "Event" : String(firstLine.prefix(80)),
            start: date,
            hasTime: hasTime
        ))]
    }

    private static func matchTrackingNumbers(in text: String) -> [Entity] {
        let lowered = text.lowercased()
        var results: [Entity] = []
        func add(_ carrier: Carrier, _ pattern: String, valid: (String) -> Bool) {
            results += matches(of: pattern, in: text).filter(valid).map { .trackingNumber(carrier, $0) }
        }
        // UPS and the 22-digit USPS shape are distinctive enough to need no carrier name, and their check digit removes
        // typos. A bare digit run passes a check one time in ten, so those need the carrier's name in the text as well.
        add(.ups, #"\b1Z[0-9A-Z]{16}\b"#, valid: TrackingCheckDigit.isValidUPS)
        add(.usps, #"\b9[1-5]\d{20}\b"#, valid: TrackingCheckDigit.isValidUSPS)
        if lowered.contains("usps") {
            add(.usps, #"\b\d{20}\b"#, valid: TrackingCheckDigit.isValidUSPS)
        }
        if lowered.contains("fedex") {
            add(.fedex, #"\b\d{12}\b"#, valid: TrackingCheckDigit.isValidFedExExpress)
            add(.fedex, #"\b\d{15}\b"#, valid: TrackingCheckDigit.isValidFedExGround)
            // Its check digit is not verified (the published algorithm does not reproduce on the whole number), so only
            // the carrier's name and the 96 prefix speak for it.
            add(.fedex, #"\b96\d{20}\b"#, valid: { _ in true })
        }
        if lowered.contains("dhl") {
            add(.dhl, #"\b\d{10,11}\b"#, valid: TrackingCheckDigit.isValidDHL)
        }
        return results
    }

    private static func matchLinks(in text: String) -> [Entity] {
        guard let detector = linkDetector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return .link(url)
        }
    }

    /// Data detectors and regular expressions are costly to build and the card menu asks for entities often, so each is
    /// built once.
    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    /// NSCache is thread-safe; Swift just cannot see it.
    private nonisolated(unsafe) static let regexCache = NSCache<NSString, NSRegularExpression>()

    private static func compiledRegex(_ pattern: String) -> NSRegularExpression? {
        if let cached = regexCache.object(forKey: pattern as NSString) { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache.setObject(regex, forKey: pattern as NSString)
        return regex
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = compiledRegex(pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

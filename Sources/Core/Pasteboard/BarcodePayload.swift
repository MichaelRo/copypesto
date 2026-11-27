// SPDX-License-Identifier: MIT
import Foundation

/// A QR code or barcode decoded on-device from a picture clip, ready for safe menu/detail actions.
public struct BarcodePayload: Equatable, Hashable, Sendable {
    public enum Kind: String, Equatable, Hashable, Sendable {
        case qr
        case aztec
        case pdf417
        case dataMatrix
        case barcode

        public var symbolName: String {
            switch self {
            case .qr, .aztec, .pdf417, .dataMatrix: "qrcode"
            case .barcode: "barcode.viewfinder"
            }
        }

        public var label: String {
            switch self {
            case .qr: String(localized: "QR Code")
            case .aztec: String(localized: "Aztec Code")
            case .pdf417: String(localized: "PDF417 Code")
            case .dataMatrix: String(localized: "Data Matrix")
            case .barcode: String(localized: "Barcode")
            }
        }
    }

    public enum Content: Equatable, Hashable, Sendable {
        case url(URL)
        case wifi(ssid: String, password: String?, security: String?, isHidden: Bool)
        case text(String)
    }

    public let kind: Kind
    public let rawValue: String
    public let content: Content

    public init?(rawValue: String, kind: Kind = .qr) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.kind = kind
        self.rawValue = trimmed
        content = Self.parse(trimmed)
    }

    /// What a UI label can safely display: Wi-Fi passwords and raw secret values are never exposed directly in menus.
    public var displaySummary: String {
        switch content {
        case let .url(url):
            return url.host ?? url.absoluteString
        case let .wifi(ssid, _, _, _):
            return String(localized: "Wi-Fi: \(ssid)")
        case let .text(value):
            let singleLine = value
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if singleLine.count <= 36 { return singleLine }
            return String(singleLine.prefix(35)) + "\u{2026}"
        }
    }

    public var urlToOpen: URL? {
        guard case let .url(url) = content else { return nil }
        return url
    }

    public var copyActionTitle: String {
        switch content {
        case .url:
            return String(localized: "Copy Link from \(kind.label)")
        case let .wifi(_, password, _, _):
            if password == nil {
                return String(localized: "Copy Wi-Fi Network")
            }
            return String(localized: "Copy Wi-Fi Password")
        case .text:
            return String(localized: "Copy \(kind.label)")
        }
    }

    public var copyableValue: String {
        switch content {
        case let .url(url): url.absoluteString
        case let .wifi(ssid, password, _, _): password ?? ssid
        case let .text(value): value
        }
    }

    public var secondaryCopyTitle: String? {
        guard case let .wifi(_, password, _, _) = content, password != nil else { return nil }
        return String(localized: "Copy Wi-Fi Network")
    }

    public var secondaryCopyValue: String? {
        guard case let .wifi(ssid, password, _, _) = content, password != nil else { return nil }
        return ssid
    }

    public var copiesAsSecret: Bool {
        if case .wifi(_, .some, _, _) = content { return true }
        return false
    }

    private static func parse(_ trimmed: String) -> Content {
        if let wifi = parseWiFi(trimmed) {
            return wifi
        }
        if case let .openInBrowser(url) = LinkOpenPolicy.action(for: trimmed) {
            return .url(url)
        }
        return .text(trimmed)
    }

    /// Parses ZXing-style `WIFI:T:<WPA|WEP|nopass>;S:<ssid>;P:<password>;H:<true|false>;;` QR codes.
    private static func parseWiFi(_ raw: String) -> Content? {
        guard raw.hasPrefix("WIFI:") else { return nil }
        let body = String(raw.dropFirst(5))
        var fields: [String: String] = [:]
        var token = ""
        var escaped = false

        func commitToken() {
            guard !token.isEmpty, let colon = token.firstIndex(of: ":") else {
                token = ""
                return
            }
            let key = String(token[..<colon])
            let value = String(token[token.index(after: colon)...])
            if !key.isEmpty {
                fields[key] = value
            }
            token = ""
        }

        for char in body {
            if escaped {
                token.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == ";" {
                commitToken()
            } else {
                token.append(char)
            }
        }
        commitToken()

        guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
        let rawPassword = fields["P"]
        let password = rawPassword?.isEmpty == false ? rawPassword : nil
        let security = fields["T"]?.isEmpty == false ? fields["T"] : nil
        let isHidden = fields["H"]?.lowercased() == "true"
        return .wifi(ssid: ssid, password: password, security: security, isHidden: isHidden)
    }
}

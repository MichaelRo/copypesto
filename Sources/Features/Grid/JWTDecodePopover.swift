// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What Escape and Return do while the popover is open. The shelf's key monitor takes both keys before the popover
/// sees them, so the open popover hands them over.
struct DecodePopoverKeys {
    var close: @MainActor () -> Void
    var copy: @MainActor () -> Void
}

enum JWTDecodeResult: Equatable {
    case decoded(JWTDecoding)
    case unreadable
}

/// What Decode JWT shows for a hidden token (ADR 0020): header and payload, the times as dates, and a plain note that
/// nothing was verified. Its text lives only in this view's inputs.
struct JWTDecodePopover: View {
    let result: JWTDecodeResult
    var now = Date()
    var onCopyPayload: (String) -> Void = { _ in }

    @Environment(\.pestoAccent) private var accent
    @FocusState private var copyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch result {
            case let .decoded(decoding):
                decodedBody(decoding)
            case .unreadable:
                Text("This is not a readable JWT.")
                    .font(.callout)
                    .pestoQuiet()
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }

    private func decodedBody(_ decoding: JWTDecoding) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Decoded JWT")
                    .font(.headline)
                Spacer()
                Self.validityText(decoding.validity(at: now), now: now).map { text in
                    Text(text)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            section("Header", json: decoding.headerJSON)
            section("Payload", json: decoding.payloadJSON)
            timeFacts(decoding)
            if decoding.hasNoSignature {
                Text("No signature: anyone could have written this.")
                    .font(.callout)
            }
            Text("Not verified: Pesto never checks the signature.")
                .font(.callout)
                .pestoQuiet()
            Button("Copy Payload") { onCopyPayload(decoding.payloadJSON) }
                .buttonStyle(.pestoCapsule(.primary))
                .keyboardShortcut(.defaultAction)
                .focused($copyFocused)
                .onAppear { copyFocused = true }
                .accessibilityIdentifier(AccessibilityID.decodeJWTCopyPayload)
        }
    }

    private func section(_ title: LocalizedStringKey, json: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .pestoQuiet()
            Group {
                if json.split(separator: "\n").count <= 9 {
                    jsonText(json)
                } else {
                    ScrollView { jsonText(json) }
                        .frame(height: 150)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func jsonText(_ json: String) -> some View {
        Text(json)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func timeFacts(_ decoding: JWTDecoding) -> some View {
        let facts: [(String, Date)] = [
            (String(localized: "Issued"), decoding.issuedAt),
            (String(localized: "Not before"), decoding.notBefore),
            (String(localized: "Expires"), decoding.expiresAt)
        ].compactMap { label, date in date.map { (label, $0) } }
        if !facts.isEmpty {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                ForEach(facts, id: \.0) { label, date in
                    GridRow {
                        Text(label).pestoQuiet()
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.callout)
                }
            }
        }
    }

    static func validityText(_ validity: JWTDecoding.Validity, now: Date) -> String? {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        switch validity {
        case let .expired(date):
            return String(localized: "Expired \(relative.localizedString(for: date, relativeTo: now))")
        case let .notYetValid(date):
            return String(localized: "Not valid until \(date.formatted(date: .abbreviated, time: .shortened))")
        case let .validUntil(date):
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.day, .hour, .minute, .second]
            let span = formatter.string(from: now, to: date) ?? ""
            return String(localized: "Valid for \(span)")
        case .noExpiry:
            return nil
        }
    }
}

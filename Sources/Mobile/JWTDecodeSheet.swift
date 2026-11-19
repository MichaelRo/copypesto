// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What Decode JWT shows for a hidden token (ADR 0020): header and payload, the times as dates and a plain note that
/// nothing was verified. Its text lives only in the app state's `decodedJWT`, and the sheet is gone with the lock.
struct JWTDecodeSheet: View {
    let result: JWTDecodeResult
    var now = Date()

    @Environment(MobileAppState.self) private var appState
    @Environment(\.pestoSurface) private var ground
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch result {
                    case let .decoded(decoding): decodedBody(decoding)
                    case .unreadable:
                        Text("This is not a readable JWT.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ground.ignoresSafeArea())
            .navigationTitle("Decoded JWT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { appState.decodedJWT = nil }
                }
                if case let .decoded(decoding) = result {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Copy Payload") { appState.copyDecodedPayload(decoding) }
                            .accessibilityIdentifier(MobileAccessibilityID.decodeJWTCopyPayload)
                    }
                }
            }
        }
        .accessibilityIdentifier(MobileAccessibilityID.decodeJWTSheet)
    }

    private func decodedBody(_ decoding: JWTDecoding) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let validity = JWTDecodingText.validityText(
                decoding.validity(at: now), now: now, calendar: calendar, locale: locale
            ) {
                Text(validity)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
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
                .foregroundStyle(.secondary)
        }
    }

    private func section(_ title: LocalizedStringKey, json: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(json)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private func timeFacts(_ decoding: JWTDecoding) -> some View {
        let facts: [(String, Date)] = [
            (String(localized: "Issued"), decoding.issuedAt),
            (String(localized: "Not before"), decoding.notBefore),
            (String(localized: "Expires"), decoding.expiresAt)
        ].compactMap { label, date in date.map { (label, $0) } }
        if !facts.isEmpty {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(facts, id: \.0) { label, date in
                    GridRow {
                        Text(label).foregroundStyle(.secondary)
                        Text(JWTDecodingText.dateText(date, calendar: calendar, locale: locale))
                    }
                    .font(.callout)
                }
            }
        }
    }
}

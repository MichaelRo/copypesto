// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Pesto

/// The Decode JWT popover (ADR 0020). Baselines are OS-specific (see `ClipboardCardTests`).
@MainActor
final class JWTDecodePopoverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func decoding(alg: String = "HS256") -> JWTDecoding {
        JWTDecoding(
            headerJSON: "{\n  \"alg\" : \"\(alg)\",\n  \"typ\" : \"JWT\"\n}",
            payloadJSON: "{\n  \"exp\" : 1799740000,\n  \"name\" : \"Ada Lovelace\",\n  \"sub\" : \"1234567890\"\n}",
            algorithm: alg,
            issuedAt: Date(timeIntervalSince1970: 1_799_736_400),
            notBefore: nil,
            expiresAt: Date(timeIntervalSince1970: 1_799_740_000)
        )
    }

    private func snapshot(
        _ result: JWTDecodeResult, scheme: ColorScheme = .light,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        let root = JWTDecodePopover(result: result, now: now)
            .padding(20)
            .background(scheme == .light ? Color(red: 0.92, green: 0.85, blue: 0.71) : Color(white: 0.13))
            .environment(\.colorScheme, scheme)
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(
                of: controller, as: .image(size: CGSize(width: 400, height: 520)),
                file: file, testName: testName, line: line
            )
        }
    }

    func test_expired() {
        snapshot(.decoded(decoding()))
    }

    func test_expired_dark() {
        snapshot(.decoded(decoding()), scheme: .dark)
    }

    func test_noSignature() {
        snapshot(.decoded(decoding(alg: "none")))
    }

    func test_unreadable() {
        snapshot(.unreadable)
    }

    func test_validityText() {
        XCTAssertEqual(
            JWTDecodePopover.validityText(.validUntil(now.addingTimeInterval(7200)), now: now), "Valid for 2 hours"
        )
        XCTAssertNil(JWTDecodePopover.validityText(.noExpiry, now: now))
    }
}

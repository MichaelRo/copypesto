// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import XCTest
@testable import Pesto

/// Measures the end-to-end latency of StorageService.ingest() for a plain-text payload.
///
/// Budget: < 50 ms per call on M1 Air. This covers the full pipeline:
/// SHA-256 dedup check, ContentClassifier, BlobEncryption, SwiftData insert, and save.
/// OCR and SourceAppResolver are excluded (no image payload, no bundle ID).
///
/// Each iteration uses a fresh in-memory ModelContainer so dedup state is clean.
final class IngestPipelinePerformanceTests: XCTestCase {
    func test_ingestText_pipelineUnder50ms() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let service = StorageService(modelContainer: container)
        let capture = PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data("Hello, budget".utf8),
            payloadString: "Hello, budget",
            contentHash: UUID().uuidString
        )
        let elapsed = try await ContinuousClock().measure { try await service.ingest(capture) }
        if !RunEnvironment.isCI {
            XCTAssertLessThan(elapsed, .milliseconds(50), "ingest budget (measured about 4 ms on an M-series Mac)")
        }
    }

    func test_ingestText_pipelineMeasured() {
        measure(metrics: [XCTClockMetric()]) {
            guard let container = try? ModelContainerSetup.makeInMemory().synced else {
                XCTFail("Failed to create in-memory container")
                return
            }
            let service = StorageService(modelContainer: container)
            let capture = PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text",
                payload: Data("Hello, performance test".utf8),
                payloadString: "Hello, performance test",
                contentHash: UUID().uuidString
            )
            let done = expectation(description: "ingest")
            Task {
                try? await service.ingest(capture)
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
        }
    }
}

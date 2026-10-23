// SPDX-License-Identifier: MIT
import XCTest
@testable import Pesto

@MainActor
final class OpenShelfIntentTests: XCTestCase {
    override func tearDown() async throws {
        ScriptingContext.openShelf = nil
    }

    func test_whenOpenShelfRuns_thenTheShelfOpensWithoutASearch() async throws {
        var requests: [String?] = []
        ScriptingContext.openShelf = { requests.append($0) }

        _ = try await OpenShelfIntent().perform()

        XCTAssertEqual(requests, [nil])
    }

    func test_whenSearchRuns_thenTheShelfOpensWithThatSearch() async throws {
        var requests: [String?] = []
        ScriptingContext.openShelf = { requests.append($0) }
        let intent = SearchPestoIntent()
        intent.query = "invoice"

        _ = try await intent.perform()

        XCTAssertEqual(requests, ["invoice"])
    }

    func test_whenAppIsNotReady_thenSearchFailsInsteadOfDoingNothing() async {
        ScriptingContext.openShelf = nil

        do {
            _ = try await OpenShelfIntent().perform()
            XCTFail("expected an error")
        } catch {}
    }

    func test_shortcutsProviderOffersAllFiveIntents() {
        XCTAssertEqual(PestoShortcuts.appShortcuts.count, 5)
    }
}

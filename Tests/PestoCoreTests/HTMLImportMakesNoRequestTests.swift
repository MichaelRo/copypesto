// SPDX-License-Identifier: MIT
import AppKit
import Network
import Synchronization
import Testing
@testable import PestoCore

@Suite("Copied HTML is never fetched from")
@MainActor
struct HTMLImportMakesNoRequestTests {
    @Test("HTML that names images, styles and frames on a local server makes no connection to it")
    func whenHTMLNamesResources_thenServerSeesNothing() async throws {
        let connections = Mutex(0)
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = Mutex<CheckedContinuation<Void, Never>?>(nil)
        listener.newConnectionHandler = { connection in
            connections.withLock { $0 += 1 }
            connection.cancel()
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            let continuation = ready.withLock { pending -> CheckedContinuation<Void, Never>? in
                defer { pending = nil }
                return pending
            }
            continuation?.resume()
        }
        await withCheckedContinuation { continuation in
            ready.withLock { $0 = continuation }
            listener.start(queue: .global())
        }
        defer { listener.cancel() }
        let port = try #require(listener.port?.rawValue)
        let base = "http://127.0.0.1:\(port)"
        let html = """
        <html><head><link rel="stylesheet" href="\(base)/a.css"><script src="\(base)/a.js"></script></head>
        <body background="\(base)/bg.png"><img src="\(base)/a.png"><iframe src="\(base)/frame.html"></iframe>
        <p style="background:url(\(base)/css.png)">Recipe</p><object data="\(base)/o"></object></body></html>
        """

        let flattened = RichTextFlattener.plainText(from: Data(html.utf8), type: .html)
        try await Task.sleep(for: .milliseconds(800))

        #expect(flattened == "Recipe")
        #expect(connections.withLock { $0 } == 0, "Pesto asked the page's server for something")
    }
}

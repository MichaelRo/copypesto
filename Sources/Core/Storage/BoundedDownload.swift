// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// Collects a response body in the chunks the network delivers, and gives up as soon as the status is not 200 or the
/// body passes `limit`, whether or not the server sent a Content-Length. Iterating `URLSession.AsyncBytes` instead
/// costs one async step per byte.
public final class BoundedDownload: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var data = Data()
        var continuation: CheckedContinuation<Data?, Never>?
        var finished = false
    }

    private let limit: Int
    private let state = Mutex(State())

    public init(limit: Int) {
        self.limit = limit
    }

    public func run(_ task: URLSessionDataTask) async -> Data? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.withLock { $0.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    public func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength <= Int64(limit) else {
            finish(nil)
            completionHandler(.cancel)
            return
        }
        if response.expectedContentLength > 0 {
            state.withLock { $0.data.reserveCapacity(Int(response.expectedContentLength)) }
        }
        completionHandler(.allow)
    }

    /// A public page can redirect to an address on this Mac or its network, so every hop is judged like the first.
    public static func allowsRedirect(to url: URL?) -> Bool {
        url.map(LinkPreviewEligibility.isEligible) ?? false
    }

    public func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard Self.allowsRedirect(to: request.url) else {
            finish(nil)
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    public func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let exceeded = state.withLock { state -> Bool in
            state.data.append(chunk)
            return state.data.count > limit
        }
        guard exceeded else { return }
        finish(nil)
        dataTask.cancel()
    }

    public func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
        finish(error == nil ? state.withLock { $0.data } : nil)
    }

    private func finish(_ result: Data?) {
        let continuation = state.withLock { state -> CheckedContinuation<Data?, Never>? in
            guard !state.finished else { return nil }
            state.finished = true
            state.data = Data()
            return state.continuation
        }
        continuation?.resume(returning: result)
    }
}

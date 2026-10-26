import Foundation
import os

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest, maximumBytes: Int) async throws -> Data
}

public struct BoundedHTTPTransport: HTTPTransport {
    private let protocolClasses: [AnyClass]?
    public init() { protocolClasses = nil }
    init(protocolClasses: [AnyClass]) { self.protocolClasses = protocolClasses }
    public func data(for request: URLRequest, maximumBytes: Int) async throws -> Data {
        guard maximumBytes > 0 else { throw StoreError(message: "Invalid response limit.") }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12
        config.protocolClasses = protocolClasses
        return try await BoundedDownload(limit: maximumBytes).run(request, configuration: config)
    }
}

// URLSession delegates run off-actor. Every mutable field is protected by this single lock;
// continuations are taken exactly once and resumed outside the lock. Remove this unchecked
// conformance when Foundation offers an actor-isolated streaming delegate contract.
private final class BoundedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var finished = false
        var data = Data()
        var continuation: CheckedContinuation<Data, any Error>?
        var task: URLSessionDataTask?
        var session: URLSession?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let limit: Int
    init(limit: Int) { self.limit = limit }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                let start = state.withLock { state in
                    guard !state.finished else { return false }
                    state.continuation = continuation; state.session = session; state.task = task
                    return true
                }
                if start { task.resume() }
                else { session.invalidateAndCancel(); continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: { self.finish(.failure(CancellationError())) }
    }

    private func finish(_ result: Result<Data, any Error>) {
        let resources = state.withLock { state -> (CheckedContinuation<Data, any Error>?, URLSession?)? in
            guard !state.finished else { return nil }
            state.finished = true
            let resources = (state.continuation, state.session)
            state.continuation = nil; state.session = nil; state.task = nil; state.data = Data()
            return resources
        }
        resources?.1?.invalidateAndCancel()
        resources?.0?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            completionHandler(.cancel)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            finish(.failure(StoreError(message: "Screenpipe returned HTTP \(status). Check its service and API token.")))
            return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(StoreError(message: "Screenpipe response exceeds the download limit.")))
            return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let tooLarge = state.withLock { state in
            guard !state.finished else { return false }
            guard data.count <= limit - state.data.count else { return true }
            state.data.append(data)
            return false
        }
        if tooLarge { finish(.failure(StoreError(message: "Screenpipe response exceeds the download limit."))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)) }
        else { finish(.success(state.withLock { $0.data })) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(StoreError(message: "Screenpipe redirects are disabled to protect local context and credentials.")))
    }
}

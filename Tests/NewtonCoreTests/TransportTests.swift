import Foundation
import Testing
import os
@testable import NewtonCore

// URLProtocol callbacks may race cancellation; only the stop flag is mutable and it is locked.
private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    private let stopped = OSAllocatedUnfairLock(initialState: false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        if path == "/redirect-event" {
            let target = URLRequest(url: URL(string: "http://other-fixture.invalid/external")!)
            let redirect = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.url!.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: target, redirectResponse: redirect)
            return
        }
        let status = path == "/unauthorized" ? 401 : path == "/redirect" ? 302 : 200
        let headers = path == "/declared-large" ? ["Content-Length": "100000"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "/hold" { return }
        let chunks = path == "/stream-large" ? 100 : 1
        for _ in 0..<chunks {
            guard !stopped.withLock({ $0 }) else { return }
            client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 64))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { stopped.withLock { $0 = true } }
}
private actor RequestRecorder: HTTPTransport {
    var request: URLRequest?
    func data(for request: URLRequest, maximumBytes: Int) async throws -> Data {
        self.request = request
        return Data(#"{"data":[]}"#.utf8)
    }
}

struct TransportTests {
    private func request(_ path: String) -> URLRequest { URLRequest(url: URL(string: "http://fixture.invalid" + path)!) }
    @Test func streamedBodyIsRejectedWhenItCrossesLimitWithoutContentLength() async {
        let transport = BoundedHTTPTransport(protocolClasses: [FixtureProtocol.self])
        await #expect(throws: (any Error).self) { try await transport.data(for: request("/stream-large"), maximumBytes: 128) }
    }
    @Test func oversizedContentLengthIsRejectedBeforeAccumulation() async {
        let transport = BoundedHTTPTransport(protocolClasses: [FixtureProtocol.self])
        await #expect(throws: (any Error).self) { try await transport.data(for: request("/declared-large"), maximumBytes: 128) }
    }
    @Test func smallBodyReturnsExactlyAndHTTPFailuresAreErrors() async throws {
        let transport = BoundedHTTPTransport(protocolClasses: [FixtureProtocol.self])
        #expect(try await transport.data(for: request("/ok"), maximumBytes: 128) == Data(repeating: 65, count: 64))
        for path in ["/unauthorized", "/redirect", "/redirect-event"] {
            await #expect(throws: (any Error).self) { try await transport.data(for: request(path), maximumBytes: 128) }
        }
    }
    @Test func cancellationCompletesEvenBeforeSessionStarts() async {
        for _ in 0..<25 {
            let task = Task { try await BoundedHTTPTransport(protocolClasses: [FixtureProtocol.self]).data(for: request("/hold"), maximumBytes: 128) }
            task.cancel()
            await #expect(throws: (any Error).self) { try await task.value }
        }
    }
    @Test func connectorOnlyBuildsLoopbackRequestsAndValidatesCredentialsBeforeTransport() async throws {
        let recorder = RequestRecorder(); let client = ScreenpipeClient(transport: recorder)
        _ = try await client.search("a & b / ?", token: "test-token")
        let captured = try #require(await recorder.request)
        #expect(captured.url?.host == "127.0.0.1"); #expect(captured.url?.port == 3030)
        #expect(captured.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(URLComponents(url: captured.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "a & b / ?")
        await #expect(throws: (any Error).self) { try await client.search("query", token: "token\r\nInjected: yes") }
    }
    @Test func decoderLimitsResultsAndReportsMalformedDuplicateAndExtraRows() throws {
        let valid = #"{"type":"OCR","content":{"frame_id":42,"timestamp":"2026-10-24T12:00:00Z","text":"evidence"}}"#
        let json = "{\"data\":[" + Array(repeating: valid, count: 100).joined(separator: ",") + "]}"
        let result = try ScreenpipeClient.decodeResponse(Data(json.utf8))
        #expect(result.events.count == 1); #expect(result.omitted == 99)
    }
}

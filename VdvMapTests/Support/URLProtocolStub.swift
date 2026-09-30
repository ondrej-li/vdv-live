import Foundation

/// `URLProtocol` that answers requests without a network, so the API client can
/// be exercised end to end.
final class URLProtocolStub: URLProtocol {
    /// Answer produced for the next request. Throw to simulate a transport
    /// failure.
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    /// Last request that reached the stub, for header assertions.
    static var lastRequest: URLRequest?

    static func reset() {
        handler = nil
        lastRequest = nil
    }

    /// Session wired to this stub.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    /// Convenience for the common "answer with this status and body" case.
    static func respond(statusCode: Int, body: Data) {
        handler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )
            guard let response else {
                throw URLError(.badServerResponse)
            }
            return (response, body)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

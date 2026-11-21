#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation
import XCTest
@testable import SAVE

@MainActor
final class LiveSourcePostTests: XCTestCase {
    func testRecognizedAliasesCanonicalizeOnlyTheRequestAndPreserveOriginal() throws {
        let cases: [(String, String, LiveSourcePostPlatform)] = [
            ("https://instagram.com/p/Ab_12-/?utm_source=private#fragment", "https://www.instagram.com/p/Ab_12-", .instagram),
            ("https://www.instagram.com/reel/Ab12?igsh=x", "https://www.instagram.com/reel/Ab12", .instagram),
            ("https://threads.com/@a.b_1/post/Ab_12-/?x=1", "https://www.threads.net/@a.b_1/post/Ab_12-", .threads),
            ("https://www.threads.com/@user/post/Code", "https://www.threads.net/@user/post/Code", .threads),
            ("https://threads.net/@user/post/Code", "https://www.threads.net/@user/post/Code", .threads),
            ("https://www.threads.net/@user/post/Code", "https://www.threads.net/@user/post/Code", .threads),
        ]
        for (raw, canonical, platform) in cases {
            let original = try XCTUnwrap(URL(string: raw))
            let source = try XCTUnwrap(LiveSourcePostURL.parse(original))
            XCTAssertEqual(source.originalURL, original)
            XCTAssertEqual(source.canonicalURL.absoluteString, canonical)
            XCTAssertEqual(source.platform, platform)
            XCTAssertEqual(source.platform.displayName, platform == .instagram ? "Instagram" : "Threads")
        }
    }

    func testRejectsUnsupportedURLsAndAuthorityOrPathAttacks() throws {
        let rejected = [
            "http://instagram.com/p/Code", "https://evil.example/p/Code",
            "https://instagram.com.evil.example/p/Code", "https://evil.instagram.com/p/Code",
            "https://instagram.com./p/Code", "https://user:password@instagram.com/p/Code",
            "https://instagram.com:443/p/Code", "https://threads.net:8443/@user/post/Code",
            "https://instagram.com/user", "https://instagram.com/explore/tags/cafe",
            "https://instagram.com/p/Code/extra", "https://instagram.com/p/",
            "https://instagram.com/p/Code%2Fextra", "https://instagram.com/%70/Code",
            "https://instagram.com/p/%41", "https://instagram.com/p/é",
            "https://threads.net/@user", "https://threads.net/@user/post/Code/extra",
            "https://threads.net/@user%2fname/post/Code", "https://threads.net/@u-ser/post/Code",
            "https://threads.net/@" + String(repeating: "a", count: 31) + "/post/Code",
            "https://instagram.com/p/" + String(repeating: "a", count: 129),
            "https://instagram.com/p/Code?x=" + String(repeating: "a", count: 2_048),
            "file:///p/Code", "javascript:alert(1)", "/p/Code",
        ]
        for raw in rejected {
            let url = try XCTUnwrap(URL(string: raw), raw)
            XCTAssertNil(LiveSourcePostURL.parse(url), raw)
        }
        XCTAssertNotNil(LiveSourcePostURL.parse(try XCTUnwrap(URL(string:
            "https://instagram.com/p/" + String(repeating: "a", count: 128)))))
    }

    func testRequestsOnlyOfficialEndpointsWithCanonicalURLAndNoToken() throws {
        for platform in LiveSourcePostPlatformFixtures.all {
            let source = try parsed(platform)
            let components = try XCTUnwrap(URLComponents(url: source.requestURL, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.scheme, "https")
            XCTAssertEqual(components.host, platform == .instagram ? "graph.facebook.com" : "graph.threads.net")
            XCTAssertEqual(components.path, platform == .instagram ? "/v27.0/instagram_oembed" : "/v1.0/oembed")
            XCTAssertEqual(components.queryItems, [URLQueryItem(name: "url", value: source.canonicalURL.absoluteString),
                                                  URLQueryItem(name: "maxwidth", value: "540")])
            XCTAssertNil(components.user)
            XCTAssertNil(components.password)
        }
    }

    func testRealReaderDecodesOnlyHTMLWithRemovedMetadataAbsentOrIgnored() async throws {
        for body in [#"{"html":"<p>Synthetic frontend</p>"}"#,
                     #"{"html":"<p>Synthetic frontend</p>","author_name":{"unexpected":true},"thumbnail_url":17}"#] {
            SourcePostURLProtocol.reset([.response(200, "application/json; charset=utf-8", Data(body.utf8), nil)])
            let reader = LiveSourcePostReader(protocolClasses: [SourcePostURLProtocol.self])
            let source = try parsed(.instagram)
            let html = try await reader.html(for: source)
            XCTAssertEqual(html, "<p>Synthetic frontend</p>")
            let request = try XCTUnwrap(SourcePostURLProtocol.requests.first)
            XCTAssertEqual(request.url, source.requestURL)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.timeoutInterval, 10)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(SourcePostURLProtocol.requests.count, 1)
        }
    }

    func testRealReaderRejectsHTTPMIMEMalformedAndEmptyHTML() async throws {
        let cases: [(SourcePostURLProtocol.Stub, LiveSourcePostError)] = [
            (.response(401, "application/json", Data(#"{"html":"private"}"#.utf8), nil), .unavailable),
            (.response(429, "application/json", Data(), nil), .unavailable),
            (.response(200, "text/html", Data("<html>Login</html>".utf8), nil), .invalid),
            (.response(200, nil, Data(#"{"html":"post"}"#.utf8), nil), .invalid),
            (.response(200, "application/json", Data("not-json".utf8), nil), .invalid),
            (.response(200, "application/json", Data(#"{"html":4}"#.utf8), nil), .invalid),
            (.response(200, "application/json", Data(#"{"title":"not html"}"#.utf8), nil), .invalid),
            (.response(200, "application/json", Data(#"{"html":" \n\t"}"#.utf8), nil), .invalid),
        ]
        for (stub, expected) in cases {
            SourcePostURLProtocol.reset([stub])
            await assertReaderFailure(expected)
            XCTAssertEqual(SourcePostURLProtocol.requests.count, 1)
        }
    }

    func testRealReaderEnforcesAdvertisedStreamAndHTMLByteBounds() async throws {
        let largeHTML = String(repeating: "a", count: 128 * 1_024 + 1)
        let bodies: [SourcePostURLProtocol.Stub] = [
            .response(200, "application/json", Data(), 256 * 1_024 + 1),
            .response(200, "application/json", Data(repeating: 32, count: 256 * 1_024 + 1), nil),
            .response(200, "application/json", try JSONSerialization.data(withJSONObject: ["html": largeHTML]), nil),
            .response(200, "application/json", try JSONSerialization.data(withJSONObject: ["html": String(repeating: "字", count: 44_000)]), nil),
        ]
        for stub in bodies {
            SourcePostURLProtocol.reset([stub])
            await assertReaderFailure(.oversize)
        }
    }

    func testRealReaderRefusesRedirectAndDoesNotRequestDestination() async throws {
        SourcePostURLProtocol.reset([.redirect(try XCTUnwrap(URL(string: "https://evil.example/collect")))])
        let reader = LiveSourcePostReader(protocolClasses: [SourcePostURLProtocol.self])
        do {
            _ = try await reader.html(for: parsed(.threads))
            XCTFail("Redirect must not produce frontend content")
        } catch { }
        XCTAssertEqual(SourcePostURLProtocol.requests.count, 1)
        XCTAssertEqual(SourcePostURLProtocol.requests.first?.url?.host, "graph.threads.net")
    }

    func testRealReaderMapsTimeoutAndRejectsForgedParsedValueBeforeTransport() async throws {
        SourcePostURLProtocol.reset([.failure(URLError(.timedOut))])
        await assertReaderFailure(.timedOut)
        SourcePostURLProtocol.reset([])
        let valid = try parsed(.instagram)
        let forged = LiveSourcePostURL(originalURL: valid.originalURL,
            canonicalURL: try XCTUnwrap(URL(string: "https://evil.example/p/Code")), platform: .instagram)
        let reader = LiveSourcePostReader(protocolClasses: [SourcePostURLProtocol.self])
        do { _ = try await reader.html(for: forged); XCTFail("Forged source") }
        catch { XCTAssertEqual(error as? LiveSourcePostError, .invalid) }
        XCTAssertTrue(SourcePostURLProtocol.requests.isEmpty)
    }

    func testRealReaderCancelStopsSuspendedTransportAndCanStartFreshRequest() async throws {
        let entered = expectation(description: "Suspended synthetic transport")
        SourcePostURLProtocol.reset([.hold(entered)])
        let reader = LiveSourcePostReader(protocolClasses: [SourcePostURLProtocol.self])
        let source = try parsed(.instagram)
        let task = Task { try await reader.html(for: source) }
        await fulfillment(of: [entered], timeout: 2)
        reader.cancel()
        do { _ = try await task.value; XCTFail("Cancelled transport cannot provide HTML") }
        catch { XCTAssertTrue(error is CancellationError) }
        SourcePostURLProtocol.reset([.response(200, "application/json", Data(#"{"html":"<p>Fresh</p>"}"#.utf8), nil)])
        let fresh = try await reader.html(for: source)
        XCTAssertEqual(fresh, "<p>Fresh</p>")
    }

    func testAlreadyCancelledReaderCallDoesNotCancelActiveBTransport() async throws {
        let entered = expectation(description: "B transport held")
        SourcePostURLProtocol.reset([.hold(entered)])
        let reader = LiveSourcePostReader(protocolClasses: [SourcePostURLProtocol.self])
        let sourceB = try parsed(.instagram)
        let sourceA = try parsed(.threads)
        let b = Task { try await reader.html(for: sourceB) }
        await fulfillment(of: [entered], timeout: 2)
        let gate = SourcePostEntryGate()
        let a = Task { await gate.wait(); return try await reader.html(for: sourceA) }
        await fulfillment(of: [gate.entered], timeout: 2)
        a.cancel()
        gate.release()
        do { _ = try await a.value; XCTFail("Already cancelled A must fail before touching B") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(SourcePostURLProtocol.requests.count, 1)
        XCTAssertEqual(SourcePostURLProtocol.requests.first?.url, sourceB.requestURL)
        SourcePostURLProtocol.completeHeld(with: Data(#"{"html":"<p>B survives</p>"}"#.utf8))
        let html = try await b.value
        XCTAssertEqual(html, "<p>B survives</p>")
    }

    func testModelDoesNotConstructReaderForStaleOwnerGenerationOrSource() async throws {
        let context = SourcePostAccessFixture()
        let source = try parsed(.instagram)
        var factories = 0
        let model = LiveSourcePostModel(readerFactory: { factories += 1; return SourcePostTestReader() })
        for mutation in 0..<3 {
            context.reset()
            context.revoke(mutation)
            await model.load(source: source, isCurrent: context.isCurrent)
            XCTAssertEqual(model.state, .idle)
            XCTAssertNil(model.html)
        }
        XCTAssertEqual(factories, 0)
    }

    func testModelPublishesFrontendOnlyAndFailureRequiresExplicitRetry() async throws {
        let reader = SourcePostTestReader()
        reader.error = LiveSourcePostError.unavailable
        let model = LiveSourcePostModel(readerFactory: { reader })
        let source = try parsed(.instagram)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(reader.calls, 0)
        await model.load(source: source, isCurrent: { true })
        XCTAssertEqual(model.state, .failed)
        XCTAssertNil(model.html)
        XCTAssertEqual(reader.calls, 1)
        reader.error = nil
        await model.load(source: source, isCurrent: { true })
        XCTAssertEqual(model.state, .available)
        XCTAssertEqual(model.html, "<p>Synthetic original post</p>")
        XCTAssertEqual(reader.sources, [source, source])
        model.cancel()
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.html)
    }

    func testModelDiscardsReplyAfterOwnerGenerationOrSourceChanges() async throws {
        for mutation in 0..<3 {
            let context = SourcePostAccessFixture()
            let reader = SourcePostTestReader()
            reader.suspend = true
            let model = LiveSourcePostModel(readerFactory: { reader })
            let source = try parsed(.threads)
            let task = Task { await model.load(source: source, isCurrent: context.isCurrent) }
            await fulfillment(of: [reader.entered], timeout: 2)
            context.revoke(mutation)
            reader.release()
            await task.value
            XCTAssertEqual(model.state, .idle)
            XCTAssertNil(model.html)
        }
    }

    func testModelRechecksCurrentImmediatelyBeforePublication() async throws {
        let reader = SourcePostTestReader()
        let model = LiveSourcePostModel(readerFactory: { reader })
        var checks = 0
        await model.load(source: try parsed(.instagram), isCurrent: {
            checks += 1
            return checks < 4
        })
        XCTAssertEqual(reader.calls, 1)
        XCTAssertEqual(checks, 4)
        XCTAssertNil(model.html)
        XCTAssertEqual(model.state, .idle)
    }

    func testExplicitAndTaskCancellationReleaseNoncooperativeReaderWithoutPublishing() async throws {
        for taskCancellation in [false, true] {
            let reader = SourcePostTestReader()
            reader.suspend = true
            let model = LiveSourcePostModel(readerFactory: { reader })
            let source = try parsed(.threads)
            let task = Task { await model.load(source: source, isCurrent: { true }) }
            await fulfillment(of: [reader.entered], timeout: 2)
            if taskCancellation { task.cancel() } else { model.cancel() }
            await task.value
            XCTAssertEqual(model.state, .idle)
            XCTAssertNil(model.html)
            XCTAssertGreaterThan(reader.cancellations, 0)
            reader.release()
            await Task.yield()
            XCTAssertNil(model.html)
        }
    }

    func testLateAAfterBAndCancelAfterPublicationNeverRestoreOldHTML() async throws {
        let first = SourcePostTestReader()
        first.suspend = true
        first.value = "<p>A</p>"
        let second = SourcePostTestReader()
        second.value = "<p>B</p>"
        var count = 0
        let model = LiveSourcePostModel(readerFactory: { count += 1; return count == 1 ? first : second })
        let sourceA = try parsed(.instagram)
        let sourceB = try parsed(.threads)
        let a = Task { await model.load(source: sourceA, isCurrent: { true }) }
        await fulfillment(of: [first.entered], timeout: 2)
        await model.load(source: sourceB, isCurrent: { true })
        await a.value
        XCTAssertEqual(model.html, "<p>B</p>")
        first.release()
        await Task.yield()
        XCTAssertEqual(model.state, .available)
        XCTAssertEqual(model.html, "<p>B</p>")
        model.cancel()
        XCTAssertNil(model.html)
        XCTAssertEqual(model.state, .idle)
    }

    func testAlreadyCancelledModelLoadDoesNotCancelOrReplaceActiveB() async throws {
        let reader = SourcePostTestReader()
        reader.suspend = true
        reader.value = "<p>B survives</p>"
        var factories = 0
        let model = LiveSourcePostModel(readerFactory: { factories += 1; return reader })
        let sourceB = try parsed(.instagram)
        let sourceA = try parsed(.threads)
        let b = Task { await model.load(source: sourceB, isCurrent: { true }) }
        await fulfillment(of: [reader.entered], timeout: 2)
        let gate = SourcePostEntryGate()
        let a = Task { await gate.wait(); await model.load(source: sourceA, isCurrent: { true }) }
        await fulfillment(of: [gate.entered], timeout: 2)
        a.cancel()
        gate.release()
        await a.value
        XCTAssertEqual(model.state, .loading)
        XCTAssertNil(model.html)
        XCTAssertEqual(factories, 1)
        XCTAssertEqual(reader.cancellations, 0)
        XCTAssertEqual(reader.sources, [sourceB])
        reader.release()
        await b.value
        XCTAssertEqual(model.state, .available)
        XCTAssertEqual(model.html, "<p>B survives</p>")
    }

    func testModelDeadlineClearsNoncooperativeRequestAndRejectsLateContent() async throws {
        let reader = SourcePostTestReader()
        reader.suspend = true
        let model = LiveSourcePostModel(readerFactory: { reader })
        let completed = expectation(description: "10 second model deadline releases load")
        let source = try parsed(.instagram)
        let task = Task { await model.load(source: source, isCurrent: { true }); completed.fulfill() }
        await fulfillment(of: [completed], timeout: 12)
        XCTAssertEqual(model.state, .failed)
        XCTAssertNil(model.html)
        XCTAssertGreaterThan(reader.cancellations, 0)
        reader.release()
        await task.value
        await Task.yield()
        XCTAssertEqual(model.state, .failed)
        XCTAssertNil(model.html)
    }

    func testModelRejectsInvalidInjectedHTML() async throws {
        for value in [" \n", String(repeating: "a", count: 128 * 1_024 + 1)] {
            let reader = SourcePostTestReader()
            reader.value = value
            let model = LiveSourcePostModel(readerFactory: { reader })
            await model.load(source: try parsed(.instagram), isCurrent: { true })
            XCTAssertEqual(model.state, .failed)
            XCTAssertNil(model.html)
        }
    }

    func testRendererFailureClearsCurrentHTMLWithoutFetchingAndExplicitLoadRetries() async throws {
        let reader = SourcePostTestReader()
        let model = LiveSourcePostModel(readerFactory: { reader })
        let source = try parsed(.instagram)
        XCTAssertNil(model.renderID)
        await model.load(source: source, isCurrent: { true })
        let firstRender = try XCTUnwrap(model.renderID)
        model.rendererFailed(renderID: firstRender, isCurrent: { true })
        XCTAssertEqual(model.state, .failed)
        XCTAssertNil(model.html)
        XCTAssertNil(model.renderID)
        XCTAssertEqual(reader.calls, 1, "Renderer failure must not automatically retry the provider")
        reader.value = "<p>Fresh explicit retry</p>"
        await model.load(source: source, isCurrent: { true })
        let secondRender = try XCTUnwrap(model.renderID)
        XCTAssertNotEqual(secondRender, firstRender)
        var staleAccessChecks = 0
        model.rendererFailed(renderID: firstRender, isCurrent: { staleAccessChecks += 1; return false })
        XCTAssertEqual(staleAccessChecks, 0, "An old attempt must not revalidate or cancel a newer request")
        XCTAssertEqual(model.state, .available)
        XCTAssertEqual(model.html, "<p>Fresh explicit retry</p>")
        XCTAssertEqual(reader.calls, 2)
    }

    func testRendererFailureAfterOwnerGenerationSourceRevocationOrCancellationCannotPublishFailure() async throws {
        for mutation in 0..<3 {
            let context = SourcePostAccessFixture()
            let model = LiveSourcePostModel(readerFactory: { SourcePostTestReader() })
            await model.load(source: try parsed(.threads), isCurrent: context.isCurrent)
            let render = try XCTUnwrap(model.renderID)
            context.revoke(mutation)
            model.rendererFailed(renderID: render, isCurrent: context.isCurrent)
            XCTAssertEqual(model.state, .idle)
            XCTAssertNil(model.html)
            XCTAssertNil(model.renderID)
            model.rendererFailed(renderID: render, isCurrent: { true })
            XCTAssertEqual(model.state, .idle)
        }
        let model = LiveSourcePostModel(readerFactory: { SourcePostTestReader() })
        await model.load(source: try parsed(.instagram), isCurrent: { true })
        let render = try XCTUnwrap(model.renderID)
        model.cancel()
        model.rendererFailed(renderID: render, isCurrent: { true })
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.html)
    }

    func testOldRendererFailureCannotCancelAnotherSourceLoadingOrItsPublishedHTML() async throws {
        let first = SourcePostTestReader()
        let second = SourcePostTestReader()
        second.suspend = true
        second.value = "<p>Different source survives</p>"
        var factories = 0
        let model = LiveSourcePostModel(readerFactory: { factories += 1; return factories == 1 ? first : second })
        await model.load(source: try parsed(.instagram), isCurrent: { true })
        let oldRender = try XCTUnwrap(model.renderID)
        let nextSource = try parsed(.threads)
        let task = Task { await model.load(source: nextSource, isCurrent: { true }) }
        await fulfillment(of: [second.entered], timeout: 2)
        model.rendererFailed(renderID: oldRender, isCurrent: { false })
        XCTAssertEqual(model.state, .loading)
        XCTAssertNil(model.renderID)
        XCTAssertEqual(second.cancellations, 0)
        second.release()
        await task.value
        model.rendererFailed(renderID: oldRender, isCurrent: { false })
        XCTAssertEqual(model.state, .available)
        XCTAssertEqual(model.html, "<p>Different source survives</p>")
    }

    private func parsed(_ platform: LiveSourcePostPlatform) throws -> LiveSourcePostURL {
        try XCTUnwrap(LiveSourcePostURL.parse(try XCTUnwrap(URL(string: platform == .instagram
            ? "https://instagram.com/p/Synthetic178?private=not-forwarded"
            : "https://threads.com/@synthetic.source/post/Synthetic178?private=not-forwarded"))))
    }

    private func assertReaderFailure(_ expected: LiveSourcePostError) async {
        do {
            let reader = LiveSourcePostReader(protocolClasses: [SourcePostURLProtocol.self])
            _ = try await reader.html(for: parsed(.instagram))
            XCTFail("Expected bounded reader failure")
        } catch { XCTAssertEqual(error as? LiveSourcePostError, expected) }
    }
}

private enum LiveSourcePostPlatformFixtures {
    static let all: [LiveSourcePostPlatform] = [.instagram, .threads]
}

@MainActor
private final class SourcePostEntryGate {
    let entered = XCTestExpectation(description: "Older task paused before method entry")
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }
    func release() { let value = continuation; continuation = nil; value?.resume() }
}

@MainActor
private final class SourcePostAccessFixture {
    var owner = "owner"
    var generation = 1
    var source = "source"
    func isCurrent() -> Bool { owner == "owner" && generation == 1 && source == "source" }
    func reset() { owner = "owner"; generation = 1; source = "source" }
    func revoke(_ component: Int) {
        if component == 0 { owner = "other" }
        else if component == 1 { generation = 2 }
        else { source = "replacement" }
    }
}

@MainActor
private final class SourcePostTestReader: LiveSourcePostReading {
    var value = "<p>Synthetic original post</p>"
    var error: Error?
    var suspend = false
    var calls = 0
    var cancellations = 0
    var sources: [LiveSourcePostURL] = []
    let entered = XCTestExpectation(description: "Synthetic reader entered")
    private var continuation: CheckedContinuation<Void, Never>?

    func html(for source: LiveSourcePostURL) async throws -> String {
        calls += 1
        sources.append(source)
        if suspend {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }
        if let error { throw error }
        return value
    }
    func cancel() { cancellations += 1 /* Deliberately ignores cancellation. */ }
    func release() { let value = continuation; continuation = nil; value?.resume() }
}

private final class SourcePostURLProtocol: URLProtocol, @unchecked Sendable {
    enum Stub {
        case response(Int, String?, Data, Int?)
        case redirect(URL)
        case failure(URLError)
        case hold(XCTestExpectation)
    }
    private static let lock = NSLock()
    // URLProtocol callbacks run outside MainActor. Every access is protected by lock.
    private nonisolated(unsafe) static var stubs: [Stub] = []
    private nonisolated(unsafe) static var recorded: [URLRequest] = []
    private nonisolated(unsafe) static var held: SourcePostURLProtocol?
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    static func reset(_ values: [Stub]) { lock.lock(); defer { lock.unlock() }; stubs = values; recorded = []; held = nil }
    static func completeHeld(with data: Data) {
        lock.lock()
        let value = held
        held = nil
        lock.unlock()
        guard let value else { XCTFail("No held synthetic transport"); return }
        value.client?.urlProtocol(value, didLoad: data)
        value.client?.urlProtocolDidFinishLoading(value)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let stub = Self.stubs.isEmpty ? Stub.failure(URLError(.resourceUnavailable)) : Self.stubs.removeFirst()
        Self.lock.unlock()
        switch stub {
        case .response(let status, let mime, let data, let length):
            var headers: [String: String] = [:]
            if let mime { headers["Content-Type"] = mime }
            if let length { headers["Content-Length"] = String(length) }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let destination):
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": destination.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: response)
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .hold(let entered):
            Self.lock.lock()
            Self.held = self
            Self.lock.unlock()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            entered.fulfill()
        }
    }
    override func stopLoading() { }
}
#endif

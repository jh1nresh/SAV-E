import XCTest
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityMVPGuideAITests: XCTestCase {
    private let venueID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private func request(_ question: String = "Which coffee?") -> CityMVPGuideSelection.Request {
        .init(version: 1, question: question, venues: [.init(placeID: venueID, name: "Cafe", category: "cafe", sources: [])])
    }
    private func response() -> CityMVPGuideSelection.Response {
        .init(choices: [.init(placeID: venueID, sourceIDs: [])])
    }
    private func envelope(_ response: CityMVPGuideSelection.Response, finish: String = "STOP") throws -> Data {
        let text = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["candidates": [["finishReason": finish, "content": ["parts": [["text": text]]]]]])
    }
    private func client(_ lifecycle: GuideLifecycleSpy) -> CityMVPGuideGeminiClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [GuideLocalURLProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel() }
        let transport = SAVEGeminiTransport(modelFallbacks: ["first-model", "must-not-fallback"], session: session,
            accessTokenProvider: { "synthetic-token" }, directAPIKey: "must-not-be-used",
            apiBaseURL: "https://guide.test.invalid", maxAttemptsPerModel: 3, transientRetryDelayNanoseconds: 1)
        return .init(transport: transport, lifecycle: lifecycle)
    }

    func testRealTransportUsesOneCorrelatedProxyCallAndFinishesAnalysis() async throws {
        GuideLocalURLProtocol.configure(status: 200, data: try envelope(response()))
        let lifecycle = GuideLifecycleSpy()
        let actual = try await client(lifecycle).choose(request())
        XCTAssertEqual(actual, response())
        let calls = GuideLocalURLProtocol.requests
        XCTAssertEqual(calls.count, 1)
        let sent = try XCTUnwrap(calls.first)
        XCTAssertEqual(sent.url?.path, "/v0/llm/gemini-generate-content")
        XCTAssertEqual(sent.authorization, "Bearer synthetic-token")
        XCTAssertEqual(sent.analysisID, lifecycle.started.first?.uuidString)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "first-model")
        let generation = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(generation["maxOutputTokens"] as? Int, 1_024)
        XCTAssertEqual(generation["candidateCount"] as? Int, 1)
        XCTAssertEqual(lifecycle.finished, ["source_only"])
    }

    func testTransientFailureAndQuotaDenialNeverRetryOrFallback() async throws {
        for (status, data) in [(503, Data("{}".utf8)), (429, Data("{\"code\":\"analysis_limit_exceeded\"}".utf8))] {
            GuideLocalURLProtocol.configure(status: status, data: data)
            let lifecycle = GuideLifecycleSpy()
            do { _ = try await client(lifecycle).choose(request()); XCTFail("Must fail") } catch {}
            XCTAssertEqual(GuideLocalURLProtocol.requests.count, 1)
            XCTAssertEqual(lifecycle.started.count, 1)
            XCTAssertEqual(lifecycle.finished, ["failed"])
        }
    }

    func testAnalysisDenialAndPreflightSizeNeverReachModel() async throws {
        GuideLocalURLProtocol.configure(status: 200, data: try envelope(response()))
        let denied = GuideLifecycleSpy(); denied.allow = false
        do { _ = try await client(denied).choose(request()); XCTFail("Must deny") }
        catch { XCTAssertEqual(error as? CityMVPGuideAIError, .analysisUnavailable) }
        XCTAssertTrue(GuideLocalURLProtocol.requests.isEmpty)
        XCTAssertEqual(denied.finished, ["failed"])
        let venues = (0..<5).map { index in
            CityMVPGuideSelection.Venue(placeID: UUID(), name: String(repeating: "N", count: 2_048), category: "cafe",
                sources: (0..<2).map { offset in .init(sourceID: String(repeating: String(index * 2 + offset), count: 64),
                    selfDeclaredSender: "Declared", reason: String(repeating: "R", count: 800), authenticatedSender: false) })
        }
        let large = CityMVPGuideSelection.Request(version: 1, question: "Which?", venues: venues)
        _ = try CityMVPGuideSelection.canonicalData(for: large)
        let untouched = GuideLifecycleSpy()
        do { _ = try await client(untouched).choose(large); XCTFail("Must fail before analysis") }
        catch { XCTAssertEqual(error as? CityMVPGuideAIError, .inputTooLarge) }
        XCTAssertTrue(untouched.started.isEmpty); XCTAssertTrue(GuideLocalURLProtocol.requests.isEmpty)
    }

    func testIncompleteOrUnknownReferencesAreRejectedAndFinishedOnce() async throws {
        let invented = CityMVPGuideSelection.Response(choices: [.init(placeID: UUID(), sourceIDs: [])])
        for data in [try envelope(response(), finish: "MAX_TOKENS"), try envelope(invented)] {
            GuideLocalURLProtocol.configure(status: 200, data: data)
            let lifecycle = GuideLifecycleSpy()
            do { _ = try await client(lifecycle).choose(request()); XCTFail("Must reject") } catch {}
            XCTAssertEqual(GuideLocalURLProtocol.requests.count, 1)
            XCTAssertEqual(lifecycle.finished, ["failed"])
        }
    }

    func testOwnerSwitchAfterAnalysisStartPreventsModelRequest() async throws {
        GuideLocalURLProtocol.configure(status: 200, data: try envelope(response()))
        let lifecycle = GuideLifecycleSpy(); var owner = "first"
        lifecycle.onStart = { owner = "second" }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [GuideLocalURLProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let transport = SAVEGeminiTransport(modelFallbacks: ["first"], session: session,
            accessTokenProvider: { "synthetic" }, directAPIKey: nil, apiBaseURL: "https://guide.test.invalid")
        let adapter = CityMVPGuideGeminiClient(transport: transport, lifecycle: lifecycle, ownerIdentity: { owner })
        do { _ = try await adapter.choose(request()); XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(GuideLocalURLProtocol.requests.isEmpty); XCTAssertEqual(lifecycle.finished, ["cancelled"])
    }

    func testControllerRejectsChangedSelectionAndLateCancelledClient() async throws {
        let client = HeldGuideClient()
        let selected = request(); var current = selected
        let controlled = CityMVPGuideAIController(client: client)
        let task = Task { await controlled.run(selected, currentRequest: { current }) }
        for _ in 0..<100 where client.pending.isEmpty { await Task.yield() }
        XCTAssertEqual(client.pending.count, 1)
        current = request("Changed question")
        client.pending.removeFirst().resume(returning: response())
        await task.value
        XCTAssertNil(controlled.response); XCTAssertFalse(controlled.isWorking)
        let cancelled = Task { await controlled.run(selected, currentRequest: { selected }) }
        for _ in 0..<100 where client.pending.isEmpty { await Task.yield() }
        XCTAssertEqual(client.pending.count, 1)
        controlled.cancel()
        client.pending.removeFirst().resume(returning: response())
        await cancelled.value
        XCTAssertNil(controlled.response); XCTAssertNil(controlled.request); XCTAssertFalse(controlled.isWorking)
    }

    func testControllerRejectsInjectedInvalidReferencesAndDisconnectedDefault() async throws {
        let unknown = CityMVPGuideSelection.Response(choices: [.init(placeID: UUID(), sourceIDs: [])])
        let client = ImmediateGuideClient(response: unknown), controller = CityMVPGuideAIController(client: client)
        let input = request()
        await controller.run(input, currentRequest: { input })
        XCTAssertNil(controller.response); XCTAssertNotNil(controller.failure)
        let offline = CityMVPGuideAIController()
        await offline.run(input, currentRequest: { input })
        XCTAssertEqual(offline.failure, .notConfigured); XCTAssertFalse(offline.isWorking)
        XCTAssertNil(CityMVPGuideGeminiClient.configured())
    }

    func testOnlyExplicitRootEndpointsAreAccepted() {
        for raw in ["http://example.com", "https://a.test/path", "https://user:secret@a.test", "https://a.test?token=x", "https://a.test/#x", " https://a.test", "https://a.test:99999", "https://a.test\u{7f}"] {
            XCTAssertNil(CityMVPGuideGeminiClient.endpoint(raw), raw)
        }
        XCTAssertEqual(CityMVPGuideGeminiClient.endpoint("https://guide.test.invalid/"), "https://guide.test.invalid")
        XCTAssertEqual(CityMVPGuideGeminiClient.endpoint("http://127.0.0.1:3000"), "http://127.0.0.1:3000")
    }

    func testOwnerSwitchHidesCompletedResponseAndPendingReply() async throws {
        var owner = "first"
        let input = request(), controller = CityMVPGuideAIController(client: ImmediateGuideClient(response: response()), ownerIdentity: { owner })
        await controller.run(input, currentRequest: { input })
        XCTAssertNotNil(controller.response); XCTAssertNotNil(controller.request)
        owner = "second"
        XCTAssertNil(controller.response); XCTAssertNil(controller.request)
        let held = HeldGuideClient(), pending = CityMVPGuideAIController(client: held, ownerIdentity: { owner })
        let task = Task { await pending.run(input, currentRequest: { input }) }
        for _ in 0..<100 where held.pending.isEmpty { await Task.yield() }
        XCTAssertEqual(held.pending.count, 1)
        owner = "third"
        held.pending.removeFirst().resume(returning: response())
        await task.value
        XCTAssertNil(pending.response); XCTAssertNil(pending.request)
    }

    func testDismissHandoffRequiresCurrentOwnerAndResolvesCurrentSavedValue() {
        let old = Place(id: venueID, name: "Original", address: "", latitude: 25, longitude: 121, category: .cafe,
            status: .wantToGo, sourcePlatform: .other, createdAt: Date(timeIntervalSince1970: 0))
        var updated = old; updated.name = "Current saved name"
        let resolve = CityMVPGuideAIController.resolveHandoff
        XCTAssertEqual(resolve(venueID, 1, 1, [updated])?.name, "Current saved name")
        XCTAssertNil(resolve(venueID, 1, 2, [updated]))
        XCTAssertNil(resolve(venueID, 1, 1, []))
        XCTAssertNil(resolve(venueID, 1, 1, [updated, old]))
        XCTAssertNil(resolve(nil, nil, 1, [updated]))
    }
}

@MainActor private final class GuideLifecycleSpy: CityMVPGuideAnalysisLifecycle {
    var started: [UUID] = [], finished: [String] = [], allow = true
    var onStart: (() -> Void)?
    func startAnalysis(id: UUID) async throws -> UUID? { started.append(id); onStart?(); return allow ? id : nil }
    func finishAnalysis(_ context: SAVEAnalysisContext, outcome: String?) async { finished.append(outcome ?? "nil") }
}
@MainActor private final class HeldGuideClient: CityMVPGuideChoosing {
    var pending: [CheckedContinuation<CityMVPGuideSelection.Response, Error>] = []
    func choose(_ request: CityMVPGuideSelection.Request) async throws -> CityMVPGuideSelection.Response {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
}
@MainActor private struct ImmediateGuideClient: CityMVPGuideChoosing {
    let response: CityMVPGuideSelection.Response
    func choose(_ request: CityMVPGuideSelection.Request) async throws -> CityMVPGuideSelection.Response { response }
}

private final class GuideLocalURLProtocol: URLProtocol, @unchecked Sendable {
    struct Captured: Sendable { let url: URL?; let authorization: String?; let analysisID: String?; let body: Data }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var reply = Data()
    nonisolated(unsafe) private static var captured: [Captured] = []
    static var requests: [Captured] { lock.lock(); defer { lock.unlock() }; return captured }
    static func configure(status: Int, data: Data) {
        lock.lock(); defer { lock.unlock() }; self.status = status; reply = data; captured = []
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while body.count <= 64 * 1_024 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lock.lock()
        Self.captured.append(.init(url: request.url, authorization: request.value(forHTTPHeaderField: "Authorization"),
            analysisID: request.value(forHTTPHeaderField: "x-save-analysis-id"), body: body))
        let status = Self.status, data = Self.reply
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

#if SAVVY_MAIN_APP && ((DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW) || SAVVY_PUBLIC_DISCOVERY_BACKEND)
import Combine
import Foundation

enum LiveSourcePostPlatform: String, Equatable {
    case instagram, threads

    var displayName: String { self == .instagram ? "Instagram" : "Threads" }
}

/// A known source URL, never evidence for a venue or permission to publish it.
struct LiveSourcePostURL: Equatable {
    let originalURL: URL
    let canonicalURL: URL
    let platform: LiveSourcePostPlatform

    static func parse(_ original: URL) -> Self? {
        guard original.absoluteString.utf8.count <= 2_048,
              var parts = URLComponents(url: original, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.port == nil, let host = parts.host?.lowercased(),
              !parts.percentEncodedPath.contains("%") else { return nil }
        let platform: LiveSourcePostPlatform
        let pattern: String
        switch host {
        case "instagram.com", "www.instagram.com":
            platform = .instagram
            pattern = #"^/(p|reel)/[A-Za-z0-9_-]{1,128}/?$"#
        case "threads.com", "www.threads.com", "threads.net", "www.threads.net":
            platform = .threads
            pattern = #"^/@[A-Za-z0-9._]{1,30}/post/[A-Za-z0-9_-]{1,128}/?$"#
        default: return nil
        }
        guard parts.percentEncodedPath.range(of: pattern, options: .regularExpression) != nil else { return nil }
        parts.scheme = "https"
        parts.host = platform == .instagram ? "www.instagram.com" : "www.threads.net"
        parts.query = nil
        parts.fragment = nil
        if parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let canonical = parts.url else { return nil }
        return Self(originalURL: original, canonicalURL: canonical, platform: platform)
    }

    var requestURL: URL {
        var parts = URLComponents(string: platform == .instagram
            ? "https://graph.facebook.com/v27.0/instagram_oembed"
            : "https://graph.threads.net/v1.0/oembed")!
        parts.queryItems = [URLQueryItem(name: "url", value: canonicalURL.absoluteString),
                            URLQueryItem(name: "maxwidth", value: "540")]
        return parts.url!
    }
}

enum LiveSourcePostError: Error, Equatable {
    case unavailable, invalid, oversize, timedOut
}

@MainActor
protocol LiveSourcePostReading {
    func html(for source: LiveSourcePostURL) async throws -> String
    func cancel()
}

/// Only the provider's frontend HTML is decoded. No metadata is retained.
@MainActor
final class LiveSourcePostReader: LiveSourcePostReading {
    private let protocolClasses: [AnyClass]?
    private var session: URLSession?

    init(protocolClasses: [AnyClass]? = nil) { self.protocolClasses = protocolClasses }

    func html(for source: LiveSourcePostURL) async throws -> String {
        try Task.checkCancellation()
        cancel()
        // Do not permit manually constructed values to bypass the parser.
        guard LiveSourcePostURL.parse(source.originalURL) == source else { throw LiveSourcePostError.invalid }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        let session = URLSession(configuration: configuration, delegate: SourcePostRedirectRefusal(), delegateQueue: nil)
        self.session = session
        defer {
            session.finishTasksAndInvalidate()
            if self.session === session { self.session = nil }
        }
        var request = URLRequest(url: source.requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw LiveSourcePostError.unavailable
            }
            let mime = http.mimeType?.lowercased() ?? ""
            guard mime == "application/json" || (mime.hasPrefix("application/") && mime.hasSuffix("+json")) else {
                throw LiveSourcePostError.invalid
            }
            let limit = 256 * 1_024
            guard response.expectedContentLength <= Int64(limit) else { throw LiveSourcePostError.oversize }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw LiveSourcePostError.oversize }
                data.append(byte)
            }
            try Task.checkCancellation()
            struct FrontendResponse: Decodable { let html: String }
            guard let response = try? JSONDecoder().decode(FrontendResponse.self, from: data) else {
                throw LiveSourcePostError.invalid
            }
            try Self.validate(response.html)
            return response.html
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? LiveSourcePostError.timedOut : .unavailable
        }
    }

    fileprivate static func validate(_ html: String) throws {
        guard html.utf8.count <= 128 * 1_024 else { throw LiveSourcePostError.oversize }
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LiveSourcePostError.invalid }
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }
}

private final class SourcePostRedirectRefusal: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Transient frontend state only; cancellation also releases a noncooperative reader's waiter.
@MainActor
final class LiveSourcePostModel: ObservableObject {
    enum State: Equatable { case idle, loading, available, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var html: String?
    private let readerFactory: @MainActor () -> any LiveSourcePostReading
    private var reader: (any LiveSourcePostReading)?
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var revision = UUID()

    // A successful HTML request owns one renderer attempt, never provider-readability proof.
    var renderID: UUID? { state == .available ? revision : nil }

    init(readerFactory: @escaping @MainActor () -> any LiveSourcePostReading = { LiveSourcePostReader() }) {
        self.readerFactory = readerFactory
    }

    func load(source: LiveSourcePostURL, isCurrent: @escaping @MainActor () -> Bool) async {
        guard !Task.isCancelled else { return }
        cancel()
        guard !Task.isCancelled, isCurrent(), LiveSourcePostURL.parse(source.originalURL) == source else { return }
        let ticket = revision
        let cancellation = SourcePostCancellation()
        let reader = readerFactory()
        self.reader = reader
        state = .loading
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter = continuation
                work = Task { [weak self] in
                    do {
                        try Task.checkCancellation()
                        guard !cancellation.isCancelled, isCurrent() else { throw CancellationError() }
                        let html = try await reader.html(for: source)
                        try Task.checkCancellation()
                        try LiveSourcePostReader.validate(html)
                        self?.finish(ticket: ticket, result: .success(html), isCurrent: isCurrent, cancellation: cancellation)
                    } catch {
                        self?.finish(ticket: ticket, result: .failure(error), isCurrent: isCurrent, cancellation: cancellation)
                    }
                }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) }
                    catch { return }
                    self?.finish(ticket: ticket, result: .failure(LiveSourcePostError.timedOut),
                                 isCurrent: isCurrent, cancellation: cancellation)
                }
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                guard let self, self.revision == ticket else { return }
                self.cancel()
            }
        }
        if Task.isCancelled, revision == ticket { cancel() }
    }

    private func finish(ticket: UUID, result: Result<String, Error>, isCurrent: @MainActor () -> Bool,
                        cancellation: SourcePostCancellation) {
        guard revision == ticket, waiter != nil else { return }
        guard !cancellation.isCancelled, isCurrent() else { cancel(); return }
        switch result {
        case .success(let value):
            guard isCurrent() else { cancel(); return }
            html = value
            guard revision == ticket, !cancellation.isCancelled, isCurrent() else { cancel(); return }
            state = .available
        case .failure(let error):
            if error is CancellationError { cancel(); return }
            html = nil
            state = .failed
        }
        releaseRequest()
    }

    func rendererFailed(renderID: UUID, isCurrent: @MainActor () -> Bool) {
        // Check the attempt before the capability: an old renderer must not cancel a newer load.
        guard revision == renderID, state == .available else { return }
        guard isCurrent() else { cancel(); return }
        revision = UUID()
        html = nil
        state = .failed
    }

    func cancel() {
        revision = UUID()
        releaseRequest()
        html = nil
        state = .idle
    }

    private func releaseRequest() {
        work?.cancel(); work = nil
        deadline?.cancel(); deadline = nil
        reader?.cancel(); reader = nil
        let continuation = waiter
        waiter = nil
        continuation?.resume()
    }
}

/// The task cancellation callback is nonisolated; it must fence publication immediately.
private nonisolated final class SourcePostCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
#endif

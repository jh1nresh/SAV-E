#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Combine
import Darwin
import ImageIO
import LinkPresentation
import UIKit
import UniformTypeIdentifiers

@MainActor
protocol LiveBusinessWebsitePhotoReading {
    func imageData(for website: URL) async throws -> Data?
    func cancel()
}

/// Ephemeral official-website preview only. The caller must supply a matched MKMapItem.url.
@MainActor
final class LiveBusinessWebsitePhotoModel: ObservableObject {
    nonisolated static let maximumImageBytes = 8 * 1_024 * 1_024
    nonisolated static let maximumImageDimension = 1_600
    enum State: Equatable { case idle, loading, loaded, missing, rejected, failed }
    @Published private(set) var image: UIImage?
    @Published private(set) var sourceURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var state: State = .idle
    private let readerFactory: @MainActor () -> any LiveBusinessWebsitePhotoReading
    private let sessionIsCurrent: @MainActor (String, Int) -> Bool
    private let timeoutNanoseconds: UInt64
    private var reader: (any LiveBusinessWebsitePhotoReading)?
    private var revision = 0

    convenience init() {
        self.init(sessionIsCurrent: { owner, generation in
            let auth = PrivyAuthService.shared
            guard case .authenticated(let current) = auth.authState else { return false }
            return current == owner && auth.sessionGeneration == generation
        })
    }

    convenience init(sessionIsCurrent: @escaping @MainActor (String, Int) -> Bool) {
        self.init(readerFactory: { LiveLinkPresentationPhotoReader() }, sessionIsCurrent: sessionIsCurrent)
    }

    init(readerFactory: @escaping @MainActor () -> any LiveBusinessWebsitePhotoReading,
         sessionIsCurrent: @escaping @MainActor (String, Int) -> Bool,
         timeoutNanoseconds: UInt64 = 8_000_000_000) {
        self.readerFactory = readerFactory
        self.sessionIsCurrent = sessionIsCurrent
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func load(website: URL?, ownerSubject: String, generation: Int) async {
        guard !Task.isCancelled else { return }
        cancel()
        guard sessionIsCurrent(ownerSubject, generation) else { return }
        guard let website else { state = .missing; return }
        guard let accepted = Self.acceptedWebsite(website) else { state = .rejected; return }
        let ticket = revision
        let currentReader = readerFactory()
        reader = currentReader; isLoading = true; state = .loading
        let deadline = Task { @MainActor [weak self, timeoutNanoseconds] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
            guard let self, self.revision == ticket else { return }
            self.cancel(); self.state = .failed
        }
        defer { deadline.cancel() }
        do {
            let data = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await currentReader.imageData(for: accepted)
            } onCancel: {
                Task { @MainActor [weak self] in
                    if self?.revision == ticket { self?.cancel() }
                }
            }
            guard ticket == revision else { return }
            guard !Task.isCancelled, sessionIsCurrent(ownerSubject, generation) else { cancel(); return }
            reader = nil; isLoading = false
            guard let data else { state = .missing; return }
            guard data.count <= Self.maximumImageBytes,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.maximumImageDimension,
                    kCGImageSourceShouldCacheImmediately: false
                  ] as CFDictionary) else { state = .failed; return }
            image = UIImage(cgImage: thumbnail); sourceURL = accepted; state = .loaded
        } catch {
            guard ticket == revision else { return }
            guard sessionIsCurrent(ownerSubject, generation) else { cancel(); return }
            reader = nil; isLoading = false
            state = error is CancellationError || Task.isCancelled ? .idle : .failed
        }
    }

    /// The owning view calls this on disappearance as well as explicit cancellation.
    func cancel() {
        revision &+= 1
        reader?.cancel(); reader = nil
        image = nil; sourceURL = nil; isLoading = false; state = .idle
    }

    nonisolated static func acceptedWebsite(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let rawHost = url.host?.lowercased() else { return nil }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = host.split(separator: ".")
        var ipv4 = in_addr()
        guard labels.count >= 2, !host.contains(":"), !host.contains("["),
              host.withCString({ inet_aton($0, &ipv4) }) == 0,
              !["localhost", "local", "internal", "lan", "home", "test", "invalid"].contains(String(labels.last ?? "")) else { return nil }
        let excluded = ["google.com", "google.cn", "googleapis.com", "googleusercontent.com", "maps.apple.com",
                        "amap.com", "gaode.com", "baidu.com", "facebook.com", "fb.com", "fb.me", "instagram.com",
                        "threads.net", "x.com", "twitter.com", "xiaohongshu.com", "xhslink.com", "dianping.com",
                        "douyin.com", "tiktok.com", "weibo.com", "weixin.qq.com", "youtube.com", "youtu.be"]
        guard !excluded.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              !labels.contains(where: { ["google", "tripadvisor", "booking", "airbnb"].contains(String($0)) }) else { return nil }
        return url
    }
}

/// Callback metadata never crosses actors. Only image bytes/errors and Sendable Progress do.
@MainActor
private final class LiveLinkPresentationPhotoReader: LiveBusinessWebsitePhotoReading {
    private var provider: LPMetadataProvider?
    private var progress: Progress?
    private var continuation: CheckedContinuation<Data?, Error>?
    private var token: UUID?

    func imageData(for website: URL) async throws -> Data? {
        cancel()
        let ticket = UUID()
        token = ticket
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let provider = LPMetadataProvider()
            provider.timeout = 8
            self.provider = provider
            provider.startFetchingMetadata(for: website) { @Sendable [weak self] metadata, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in self.finish(ticket, .failure(error)) }
                    return
                }
                guard let metadata,
                      LiveBusinessWebsitePhotoModel.acceptedWebsite(metadata.url ?? website) != nil,
                      let imageProvider = metadata.imageProvider,
                      let type = imageProvider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                    Task { @MainActor in self.finish(ticket, .success(nil)) }
                    return
                }
                // Read the provider's temporary file inside its callback, with a hard byte cap.
                let progress = imageProvider.loadFileRepresentation(forTypeIdentifier: type) { @Sendable [weak self] file, error in
                    guard let self else { return }
                    let result: Result<Data?, Error> = Result {
                        if let error { throw error }
                        guard let file else { return nil }
                        let limit = LiveBusinessWebsitePhotoModel.maximumImageBytes
                        if let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit {
                            throw CocoaError(.fileReadTooLarge)
                        }
                        let handle = try FileHandle(forReadingFrom: file)
                        defer { try? handle.close() }
                        let data = try handle.read(upToCount: limit + 1) ?? Data()
                        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
                        return data
                    }
                    Task { @MainActor in
                        self.finish(ticket, result)
                    }
                }
                Task { @MainActor in
                    guard self.token == ticket else { progress.cancel(); return }
                    self.progress = progress
                }
            }
        }
    }

    func cancel() {
        token = nil
        let pending = continuation; continuation = nil
        provider?.cancel(); provider = nil
        progress?.cancel(); progress = nil
        pending?.resume(throwing: CancellationError())
    }

    private func finish(_ ticket: UUID, _ result: Result<Data?, Error>) {
        guard token == ticket else { return }
        token = nil
        let pending = continuation; continuation = nil
        provider = nil; progress = nil
        pending?.resume(with: result)
    }
}
#endif

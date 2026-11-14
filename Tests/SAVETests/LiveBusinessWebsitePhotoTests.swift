#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import UIKit
import XCTest
@testable import SAVE

@MainActor
final class LiveBusinessWebsitePhotoTests: XCTestCase {
    private let website = URL(string: "https://cafe.example.com/")!

    func testMissingAndUnsafeWebsitesNeverStartReader() async throws {
        let reader = WebsiteFixtureReader(result: .success(nil))
        let model = model(reader)
        await model.load(website: nil, ownerSubject: "fixture", generation: 1)
        XCTAssertEqual(model.state, .missing)
        let unsafe = ["http://cafe.example.com", "https://user:password@cafe.example.com", "https://127.0.0.1",
                      "https://2130706433", "https://0x7f000001", "https://[::1]/", "https://localhost",
                      "https://cafe.local", "https://cafe.internal", "https://maps.apple.com/", "https://maps.google.com/",
                      "https://map.baidu.com", "https://amap.com", "https://www.facebook.com/cafe", "https://instagram.com/cafe",
                      "https://xiaohongshu.com", "https://xhslink.com", "https://dianping.com", "https://tripadvisor.co.uk",
                      "https://booking.com", "https://airbnb.com"]
        for value in unsafe {
            await model.load(website: try XCTUnwrap(URL(string: value)), ownerSubject: "fixture", generation: 1)
            XCTAssertEqual(model.state, .rejected, value)
        }
        XCTAssertEqual(reader.calls, 0)
        XCTAssertNil(model.image)
        XCTAssertNil(model.sourceURL)
    }

    func testImageBytesProduceBoundedThumbnailAndOriginalWebsiteAttribution() async throws {
        let reader = WebsiteFixtureReader(result: .success(try imageData(width: 1_800)))
        let model = model(reader)
        await model.load(website: website, ownerSubject: "fixture", generation: 1)
        let image = try XCTUnwrap(model.image?.cgImage)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 1_600)
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertEqual(model.sourceURL, website)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertFalse(model.isLoading)
    }

    func testMissingMalformedAndOversizedImageDataNeverBecomePhotos() async {
        let results: [Data?] = [nil, Data("Website title is not an image".utf8),
                               Data(repeating: 0, count: LiveBusinessWebsitePhotoModel.maximumImageBytes + 1)]
        for (index, data) in results.enumerated() {
            let model = model(WebsiteFixtureReader(result: .success(data)))
            await model.load(website: website, ownerSubject: "fixture", generation: 1)
            XCTAssertEqual(model.state, index == 0 ? .missing : .failed)
            XCTAssertNil(model.image)
            XCTAssertNil(model.sourceURL)
        }
    }

    func testCancelClearsStateAndIgnoresLateImage() async throws {
        let reader = WebsiteFixtureReader(ignoresCancellation: true)
        let model = model(reader)
        let task = Task { await model.load(website: website, ownerSubject: "fixture", generation: 1) }
        await reader.waitForStart()
        model.cancel()
        XCTAssertFalse(model.isLoading)
        reader.complete(try imageData())
        await task.value
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.image)
        XCTAssertNil(model.sourceURL)
    }

    func testChangedSessionCannotPublishAwaitedImage() async throws {
        var current = true
        let reader = WebsiteFixtureReader()
        let model = LiveBusinessWebsitePhotoModel(readerFactory: { reader }, sessionIsCurrent: { _, _ in current })
        let task = Task { await model.load(website: website, ownerSubject: "fixture", generation: 1) }
        await reader.waitForStart()
        current = false
        reader.complete(try imageData())
        await task.value
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.image)
        XCTAssertNil(model.sourceURL)
    }

    func testNewWebsiteCannotBeReplacedByOldResponse() async throws {
        let stale = WebsiteFixtureReader(ignoresCancellation: true)
        let fresh = WebsiteFixtureReader(result: .success(try imageData()))
        var readers = [stale, fresh]
        let model = LiveBusinessWebsitePhotoModel(readerFactory: { readers.removeFirst() }, sessionIsCurrent: { _, _ in true })
        let oldTask = Task { await model.load(website: website, ownerSubject: "fixture", generation: 1) }
        await stale.waitForStart()
        let next = URL(string: "https://another.example.com/")!
        await model.load(website: next, ownerSubject: "fixture", generation: 1)
        stale.complete(try imageData())
        await oldTask.value
        XCTAssertEqual(model.sourceURL, next)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertNotNil(model.image)
    }

    func testDeadlineCancelsReaderWithoutPublishingLateContent() async {
        let reader = WebsiteFixtureReader()
        let model = LiveBusinessWebsitePhotoModel(readerFactory: { reader }, sessionIsCurrent: { _, _ in true },
                                                 timeoutNanoseconds: 1_000_000)
        await model.load(website: website, ownerSubject: "fixture", generation: 1)
        XCTAssertEqual(reader.cancellations, 1)
        XCTAssertEqual(model.state, .failed)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.image)
    }

    private func model(_ reader: WebsiteFixtureReader) -> LiveBusinessWebsitePhotoModel {
        LiveBusinessWebsitePhotoModel(readerFactory: { reader }, sessionIsCurrent: { _, _ in true })
    }

    private func imageData(width: Int = 80) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: 100), format: format).image { context in
            UIColor.systemBlue.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: 100))
        }
        return try XCTUnwrap(image.pngData())
    }
}

@MainActor
private final class WebsiteFixtureReader: LiveBusinessWebsitePhotoReading {
    let result: Result<Data?, Error>?
    let ignoresCancellation: Bool
    private(set) var calls = 0
    private(set) var cancellations = 0
    private var pending: CheckedContinuation<Data?, Error>?
    private var started: CheckedContinuation<Void, Never>?
    init(result: Result<Data?, Error>? = nil, ignoresCancellation: Bool = false) {
        self.result = result; self.ignoresCancellation = ignoresCancellation
    }
    func imageData(for website: URL) async throws -> Data? {
        calls += 1
        started?.resume(); started = nil
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitForStart() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func complete(_ data: Data?) { let value = pending; pending = nil; value?.resume(returning: data) }
    func cancel() {
        cancellations += 1
        if !ignoresCancellation { let value = pending; pending = nil; value?.resume(throwing: CancellationError()) }
    }
}
#endif

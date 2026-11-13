import XCTest
import SceneKit
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityScenePreparationTests: XCTestCase {
    func testProgressiveAssemblyReturnsACompleteDistrict() async throws {
        let scene = try await CitySceneGeometry.prepareScene()
        let root = scene.rootNode
        for name in [
            "xinyi-civic-landscape",
            "xinyi-raised-walkways",
            "surface-way/142113976",
            "surface-landmark-101",
            "xinyi-ground-shadows",
            CityStreetTraffic.nodeName,
        ] {
            XCTAssertNotNil(root.childNode(withName: name, recursively: false), name)
        }
        XCTAssertTrue(root.childNodes.contains { $0.name?.hasPrefix("xinyi-facade-batch-") == true })
    }

    func testCancelledPreparationDoesNotReturnAPartialScene() async {
        let assembly = Task { @MainActor in
            _ = try await CitySceneGeometry.prepareScene()
        }
        assembly.cancel()
        do {
            _ = try await assembly.value
            XCTFail("Cancelled assembly published a scene")
        } catch is CancellationError {
            // Cancellation is distinct from a successfully prepared scene.
        } catch {
            XCTFail("Unexpected assembly failure: \(error)")
        }
    }
}

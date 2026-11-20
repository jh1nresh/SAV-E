#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import MapKit
import XCTest
@testable import SAVE

@MainActor
final class LiveRoutePlanTests: XCTestCase {
    private let listID = UUID()

    func testCompletedPlanKeepsOrderDepartureAndProgressAfterRevalidatedReturn() async throws {
        let model = model()
        let stops = try fixtures()
        let departure = Date(timeIntervalSince1970: 1_800_000_000)
        model.beginsAt = departure
        await model.build(stops, listID: listID)
        model.start(); model.advance()
        model.suspendForNavigation(); model.suspendForNavigation()
        XCTAssertFalse(model.isAccessValidated)
        XCTAssertEqual(model.stops.map(\.id), stops.map(\.id))
        model.advance()
        XCTAssertEqual(model.currentIndex, 1, "Suspended controls cannot advance a retained plan")
        model.reconcile(listID: listID, places: Array(stops.reversed()))
        XCTAssertTrue(model.isAccessValidated)
        XCTAssertTrue(model.started)
        XCTAssertEqual(model.currentIndex, 1)
        XCTAssertEqual(model.beginsAt, departure)
        XCTAssertEqual(model.stops.map(\.id), stops.map(\.id), "Refreshing the list must not reorder the itinerary")
        model.advance(); model.advance()
        XCTAssertEqual(model.currentIndex, stops.count)
    }

    func testRevokedMissingOrChangedListClearsRetainedPlan() async throws {
        let stops = try fixtures()
        for id in [nil, UUID()] as [UUID?] {
            let model = model(); await model.build(stops, listID: listID); model.start()
            model.suspendForNavigation(); model.reconcile(listID: id, places: stops)
            XCTAssertTrue(model.stops.isEmpty)
            XCTAssertTrue(model.routes.isEmpty)
            XCTAssertFalse(model.started)
            XCTAssertNil(model.listID)
        }
        let model = model(); await model.build(stops, listID: listID)
        model.suspendForNavigation(); model.reconcile(listID: listID, places: [stops[0]])
        XCTAssertFalse(model.isAccessValidated)
        XCTAssertTrue(model.stops.isEmpty)
    }

    func testSameIDsWithChangedVenueDataOrDuplicateIdentityDoNotRestore() async throws {
        for change in 0..<5 {
            let stops = try fixtures(); var changedPlace = stops[0].place
            switch change {
            case 0: changedPlace.name += "別館"
            case 1: changedPlace.address += "2樓"
            case 2: changedPlace.latitude += 0.001
            case 3: changedPlace.category = changedPlace.category == .food ? .cafe : .food
            default: break
            }
            var changed = stops; changed[0] = try XCTUnwrap(LiveMapPlace.saved(changedPlace))
            if change == 4 { changed.append(changed[0]) }
            let model = model(); await model.build(stops, listID: listID)
            model.suspendForNavigation(); model.reconcile(listID: listID, places: changed)
            XCTAssertFalse(model.isAccessValidated, "Change \(change)")
            XCTAssertTrue(model.stops.isEmpty, "Change \(change)")
        }
    }

    func testAccountChangeCannotRestoreOldPlan() async throws {
        var current = true
        let model = LiveRoutePlan(ownerSubject: "fixture", sessionGeneration: 1,
                                  makeDirections: { _ in ImmediateWalkingDirections() }, sessionIsCurrent: { current })
        let stops = try fixtures(); await model.build(stops, listID: listID); model.start()
        current = false
        model.suspendForNavigation(); model.reconcile(listID: listID, places: stops)
        model.start(); model.advance()
        XCTAssertTrue(model.stops.isEmpty)
        XCTAssertFalse(model.isAccessValidated)
        XCTAssertFalse(model.started)
    }

    func testSuspensionCancelsPendingDirectionsAndRejectsLateRoute() async throws {
        let reader = HeldWalkingDirections()
        let model = LiveRoutePlan(ownerSubject: "fixture", sessionGeneration: 1,
                                  makeDirections: { _ in reader }, sessionIsCurrent: { true })
        let stops = try fixtures()
        let operation = Task { await model.build(stops, listID: listID) }
        await fulfillment(of: [reader.entered], timeout: 2)
        model.suspendForNavigation()
        XCTAssertEqual(reader.cancellations, 1)
        reader.release()
        await operation.value
        XCTAssertTrue(model.stops.isEmpty)
        XCTAssertTrue(model.routes.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isAccessValidated)
    }

    func testReplanningAndExplicitCancelDiscardOldProgress() async throws {
        let model = model(); let stops = try fixtures()
        await model.build(stops, listID: listID); model.start(); model.advance()
        await model.build(Array(stops.reversed()), listID: listID)
        XCTAssertFalse(model.started)
        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertEqual(model.stops.map(\.id), stops.reversed().map(\.id))
        model.cancel()
        XCTAssertTrue(model.stops.isEmpty)
        XCTAssertNil(model.listID)
        XCTAssertFalse(model.isAccessValidated)
    }

    func testBuildUsesWalkingRequestsAndNeverChangesVisitedState() async throws {
        var requests: [MKDirections.Request] = []
        let model = LiveRoutePlan(ownerSubject: "fixture", sessionGeneration: 1, makeDirections: {
            requests.append($0); return ImmediateWalkingDirections()
        }, sessionIsCurrent: { true })
        let stops = try fixtures(); await model.build(stops, listID: listID)
        model.start(); model.advance(); model.advance()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.transportType, .walking)
        XCTAssertEqual(requests.first?.source?.placemark.coordinate.latitude, stops[0].coordinate.latitude)
        XCTAssertEqual(requests.first?.destination?.placemark.coordinate.latitude, stops[1].coordinate.latitude)
        XCTAssertTrue(model.stops.allSatisfy { $0.place.status == .wantToGo })
    }

    private func model() -> LiveRoutePlan {
        LiveRoutePlan(ownerSubject: "fixture", sessionGeneration: 1,
                      makeDirections: { _ in ImmediateWalkingDirections() }, sessionIsCurrent: { true })
    }

    private func fixtures() throws -> [LiveMapPlace] {
        try (0..<2).map { index in
            let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 25.03 + Double(index) / 1_000, longitude: 121.54)))
            item.name = "測試地點 \(index + 1)"
            let candidate = try XCTUnwrap(LiveMapPlace.search(item))
            return try XCTUnwrap(LiveMapPlace.saved(candidate.place))
        }
    }
}

@MainActor
private final class ImmediateWalkingDirections: LiveWalkingDirections {
    func route() async throws -> MKRoute { MKRoute() }
    func cancel() {}
}

@MainActor
private final class HeldWalkingDirections: LiveWalkingDirections {
    let entered = XCTestExpectation(description: "Route awaits network")
    private var continuation: CheckedContinuation<MKRoute, Error>?
    private(set) var cancellations = 0
    func route() async throws -> MKRoute {
        try await withCheckedThrowingContinuation { continuation = $0; entered.fulfill() }
    }
    func cancel() { cancellations += 1 }
    func release() { continuation?.resume(returning: MKRoute()); continuation = nil }
}
#endif

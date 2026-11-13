import XCTest
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityLatencyObservationTests: XCTestCase {
    func testObservationRequiresSimulatorBothExplicitFlagsAndSafeUniqueID() {
        let flags = ["--inspect-citylab", "--inspect-citylab-latency"]
        let env = ["CITY_LATENCY_TEST_ID": "latency-test-123456"]
        XCTAssertEqual(CityMVPLatencyObservation.requestedID(arguments: flags, environment: env, simulator: true), env.values.first)
        XCTAssertNil(CityMVPLatencyObservation.requestedID(arguments: flags, environment: env, simulator: false))
        XCTAssertNil(CityMVPLatencyObservation.requestedID(arguments: [flags[0]], environment: env, simulator: true))
        XCTAssertNil(CityMVPLatencyObservation.requestedID(arguments: [flags[1]], environment: env, simulator: true))
        XCTAssertNil(CityMVPLatencyObservation.requestedID(arguments: flags, environment: [:], simulator: true))
        for invalid in ["../other-file", "bad/id-123456", "test id 123456", String(repeating: "a", count: 81)] {
            XCTAssertNil(CityMVPLatencyObservation.requestedID(arguments: flags,
                environment: ["CITY_LATENCY_TEST_ID": invalid], simulator: true))
        }
        XCTAssertEqual(CityMVPPreviewConfiguration.route(arguments: flags, unitTestHost: false), .preview)
        XCTAssertFalse(CityMVPLatencyObservation.isRecording, "Ordinary unit host must not start telemetry")
    }

    func testRecorderBoundsWritesRejectsInvalidNumbersAndNeverOverwrites() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("latency-unit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let recorder = try XCTUnwrap(CityMVPLatencyObservation.Recorder(url: file, maximumBytes: 512))
        defer { recorder.close() }
        XCTAssertTrue(recorder.append(.heartbeat, uptime: 1, values: ["playing": 0]))
        let first = try Data(contentsOf: file)
        XCTAssertFalse(recorder.append(.nativeUpdate, uptime: 2, values: ["distance": .nan]))
        XCTAssertEqual(try Data(contentsOf: file), first)
        XCTAssertNil(CityMVPLatencyObservation.Recorder(url: file))
        for index in 0..<20 { recorder.append(.heartbeat, uptime: Double(index + 3)) }
        XCTAssertFalse(recorder.isOpen)
        let result = try Data(contentsOf: file)
        XCTAssertLessThanOrEqual(result.count, 512)
        for line in try XCTUnwrap(String(data: result, encoding: .utf8)).split(separator: "\n") {
            _ = try JSONDecoder().decode(CityMVPLatencyObservation.Record.self, from: Data(line.utf8))
        }
    }
    func testRecorderClosesAtDeadlineAndAtRecordLimit() throws {
        let first = FileManager.default.temporaryDirectory.appendingPathComponent("latency-deadline-" + UUID().uuidString)
        let second = FileManager.default.temporaryDirectory.appendingPathComponent("latency-count-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let timed = try XCTUnwrap(CityMVPLatencyObservation.Recorder(url: first, deadline: 120))
        XCTAssertTrue(timed.append(.started, uptime: 0))
        XCTAssertTrue(timed.append(.heartbeat, uptime: 119.999))
        let before = try Data(contentsOf: first)
        XCTAssertFalse(timed.append(.heartbeat, uptime: 120)); XCTAssertFalse(timed.isOpen)
        XCTAssertEqual(try Data(contentsOf: first), before)
        let counted = try XCTUnwrap(CityMVPLatencyObservation.Recorder(url: second))
        for index in 0..<512 { XCTAssertTrue(counted.append(.heartbeat, uptime: Double(index))) }
        XCTAssertFalse(counted.append(.heartbeat, uptime: 513)); XCTAssertFalse(counted.isOpen)
        let lines = try XCTUnwrap(String(data: Data(contentsOf: second), encoding: .utf8)).split(separator: "\n")
        XCTAssertEqual(lines.count, 512)
    }

}

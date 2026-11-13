#if SAVVY_CITY_MVP
import Foundation
import MapKit
import SwiftUI
import Darwin

/// Explicit, simulator-only diagnostics. No observable/UI state or default log.
@MainActor
enum CityMVPLatencyObservation {
    nonisolated enum Event: String, Codable { case started, heartbeat, nativeUpdate, nativeEnd, mount, disappear }
    nonisolated struct Record: Codable { let event: Event; let uptime: Double; let values: [String: Double] }

    final class Recorder {
        private var handle: FileHandle?
        private var written = 0
        private var records = 0
        private let maximumBytes: Int
        private let deadline: Double?
        var isOpen: Bool { handle != nil }

        init?(url: URL, maximumBytes: Int = 128 * 1_024, deadline: Double? = nil) {
            guard url.isFileURL, maximumBytes >= 256, maximumBytes <= 128 * 1_024,
                  deadline.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }
            let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(S_IRUSR | S_IWUSR))
            }
            guard fd >= 0 else { return nil }
            do {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            } catch { Darwin.close(fd); return nil }
            handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            self.maximumBytes = maximumBytes
            self.deadline = deadline
        }

        @discardableResult
        func append(_ event: Event, uptime: Double, values: [String: Double] = [:]) -> Bool {
            if let deadline, uptime >= deadline { close(); return false }
            guard let handle, uptime.isFinite, uptime >= 0, values.values.allSatisfy(\.isFinite),
                  let data = try? JSONEncoder().encode(Record(event: event, uptime: uptime, values: values)) else { return false }
            guard records < 512, written + data.count + 1 <= maximumBytes else { close(); return false }
            do {
                try handle.write(contentsOf: data + Data([10]))
                written += data.count + 1; records += 1
                return true
            } catch { close(); return false }
        }

        func close() { try? handle?.close(); handle = nil }
    }

    private static var recorder: Recorder?
    private static var heartbeat: Task<Void, Never>?
    private static var sceneStatus: (() -> [String: Double]?)?
    private static var lastNativeUpdate = -Double.infinity
    private static var deadline = -Double.infinity
    static var isRecording: Bool { recorder?.isOpen == true && ProcessInfo.processInfo.systemUptime < deadline }

    nonisolated static func requestedID(arguments: [String], environment: [String: String], simulator: Bool) -> String? {
        guard simulator, arguments.contains("--inspect-citylab"), arguments.contains("--inspect-citylab-latency"),
              let id = environment["CITY_LATENCY_TEST_ID"], (12...80).contains(id.utf8.count),
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 }) else { return nil }
        return id
    }

    static func startIfRequested() {
#if targetEnvironment(simulator)
        guard recorder == nil, CityMVPPreviewConfiguration.enabled,
              let id = requestedID(arguments: ProcessInfo.processInfo.arguments,
                                   environment: ProcessInfo.processInfo.environment, simulator: true) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("citylab-latency-" + id + ".jsonl")
        let began = ProcessInfo.processInfo.systemUptime
        guard let writer = Recorder(url: url, deadline: began + 120) else { return }
        recorder = writer
        deadline = began + 120
        writer.append(.started, uptime: began)
        heartbeat = Task { @MainActor in
            while !Task.isCancelled && writer.isOpen && ProcessInfo.processInfo.systemUptime - began < 120 {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                writer.append(.heartbeat, uptime: ProcessInfo.processInfo.systemUptime, values: sceneStatus?() ?? [:])
            }
            writer.close(); sceneStatus = nil
        }
#endif
    }

    static func observeScene(_ provider: @escaping () -> [String: Double]?) {
        guard isRecording else { return }
        sceneStatus = provider
    }

    static func camera(_ camera: MapCamera, settled: Bool) {
        guard isRecording else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard settled || now - lastNativeUpdate >= 0.2 else { return }
        lastNativeUpdate = now
        recorder?.append(settled ? .nativeEnd : .nativeUpdate, uptime: now, values: [
            "latitude": camera.centerCoordinate.latitude, "longitude": camera.centerCoordinate.longitude,
            "distance": camera.distance, "heading": camera.heading, "pitch": camera.pitch
        ])
    }

    static func note(_ event: Event) {
        guard isRecording else { return }
        recorder?.append(event, uptime: ProcessInfo.processInfo.systemUptime)
    }
}
#endif

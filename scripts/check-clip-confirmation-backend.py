#!/usr/bin/env python3
"""Run actual strict Clip entrypoints against real service no-op guards.

The service configuration accessor and fetch/save implementation are extracted
verbatim; unrelated platform row encoding and lower UI/mirror work are stubs.
Native tests additionally instantiate SupabaseService(apiBaseURL: nil).
"""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
map_source = (ROOT / 'SAV-E/ViewModels/MapViewModel.swift').read_text()
service_source = (ROOT / 'SAV-E/Services/SupabaseService.swift').read_text()
def method(source, marker):
    begin = source.index(marker)
    brace = source.index('{', begin)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end] + "\n"
entry = method(map_source, '    func saveSharedPlaceReceipt(')
list_entry = method(map_source, '    func saveClipListHandoff(')
configured = method(service_source, 'var isConfigured: Bool {\n        apiBaseURL')
fetch = method(service_source, '    func fetchPlaces(for userId: String) async throws -> [Place] {')
save = method(service_source, '    func savePlace(_ place: Place, userId: String) async throws {')
encode = method(service_source, '    func encodedForRemoteWrite() throws -> Data {')
source = r'''
import Foundation
enum SupabaseError: Error { case notConfigured, notAuthenticated }
struct Place: Codable { var id = UUID() }
struct PlaceRow: Codable {
    static func from(place: Place, userId: String) -> Self { Self() }
    func toPlace() -> Place { Place() }
''' + encode + r'''
}
extension JSONEncoder { static var supabase: JSONEncoder { JSONEncoder() } }
extension JSONDecoder { static var supabase: JSONDecoder { JSONDecoder() } }
struct SharedPlaceReceipt { var duplicate: Bool }
enum SharedPlaceSaveOutcome { case saved, duplicate }
struct PendingSharePayload {}
enum PendingShareStore { static func load() -> PendingSharePayload? { nil } }
struct SaveListItem {}
struct SaveCollaborativeList {}
struct ClipListHandoffCounts {}
enum SAVEPendingImportSessionScope {
    @TaskLocal static var current: (generation: Int, owner: String)?
}
@MainActor final class Auth { var currentUserId: String? = "owner"; var sessionGeneration = 1 }
@MainActor final class Service {
    let apiBaseURL: URL?
    var requests = 0
    init(configured: Bool) { apiBaseURL = configured ? URL(string: "https://example.invalid") : nil }
    func mappedSavedPlaceLimit(_ error: Error) -> Error { error }
    @discardableResult func request(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        requests += 1; return Data("[]".utf8)
    }
''' + configured + fetch + save + r'''
}
@MainActor final class Model {
    let authService = Auth()
    let supabaseService: Service
    var usesRemotePersistence = true
    var mutations = 0
    var duplicateMerges = 0
    init(_ service: Service) { supabaseService = service }
''' + entry + list_entry + r'''
    private func saveSharedPlaceReceiptForSession(_ receipt: SharedPlaceReceipt, owner: String?, generation: Int,
        requiringAuthenticatedSession: Bool, journal: PendingSharePayload?) async throws -> SharedPlaceSaveOutcome {
        _ = try await supabaseService.fetchPlaces(for: owner!)
        try await supabaseService.savePlace(Place(), userId: owner!)
        mutations += 1
        if receipt.duplicate { duplicateMerges += 1; return .duplicate }
        return .saved
    }
    private func saveClipListHandoff(_ list: SaveCollaborativeList, owner: String?, generation: Int,
        requiringAuthenticatedSession: Bool) async throws -> (toStamp: [SaveListItem], counts: ClipListHandoffCounts) {
        mutations += 1; return ([], ClipListHandoffCounts())
    }
}
@main struct Check {
    @MainActor static func main() async throws {
        let realNoOp = Service(configured: false)
        try await realNoOp.savePlace(Place(), userId: "owner")
        precondition(try await realNoOp.fetchPlaces(for: "owner").isEmpty)
        precondition(realNoOp.requests == 0)
        var failures = 0
        for duplicate in [false, true] {
            let model = Model(realNoOp)
            do {
                _ = try await model.saveSharedPlaceReceipt(SharedPlaceReceipt(duplicate: duplicate), requiringAuthenticatedSession: true)
                failures += 1
            } catch SupabaseError.notConfigured {}
            if model.mutations != 0 { failures += 1 }
        }
        let missingList = Model(realNoOp)
        do { _ = try await missingList.saveClipListHandoff(SaveCollaborativeList(), requiringAuthenticatedSession: true); failures += 1 }
        catch SupabaseError.notConfigured {}
        for duplicate in [false, true] {
            let configured = Model(Service(configured: true))
            _ = try await configured.saveSharedPlaceReceipt(SharedPlaceReceipt(duplicate: duplicate), requiringAuthenticatedSession: true)
            precondition(configured.mutations == 1 && configured.supabaseService.requests == 2)
        }
        let local = Model(Service(configured: true)); local.usesRemotePersistence = false
        do { _ = try await local.saveSharedPlaceReceipt(SharedPlaceReceipt(duplicate: true), requiringAuthenticatedSession: true); failures += 1 }
        catch SupabaseError.notConfigured {}
        let legacy = Model(realNoOp)
        _ = try await legacy.saveSharedPlaceReceipt(SharedPlaceReceipt(duplicate: false))
        precondition(legacy.mutations == 1, "Ordinary offline behavior is preserved")
        if failures > 0 {
            print("FAIL: strict confirmation accepted nonthrowing unconfigured/local-only service (\(failures) assertions)")
            exit(1)
        }
        print("PASS: real service nil-configuration fetch/save no-op demonstrated; strict receipt new/duplicate/list entrypoints reject before mutation; configured success and ordinary offline route preserved")
    }
}
'''
# async/throwing work cannot appear inside precondition's autoclosure.
source = source.replace('precondition(try await realNoOp.fetchPlaces(for: "owner").isEmpty)', 'let empty = try await realNoOp.fetchPlaces(for: "owner"); precondition(empty.isEmpty)')
with tempfile.TemporaryDirectory(prefix='clip-backend-gate-') as directory:
    out = Path(directory)
    (out / 'Check.swift').write_text(source)
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', str(out / 'Check.swift'), '-o', str(out / 'check')], check=True)
    subprocess.run([str(out / 'check')], check=True)

#!/usr/bin/env python3
"""Run actual photo-map visit transactions and shared Passport history on macOS.

Only platform Place/auth/network/vault interfaces are stand-ins. Production
updatePlace, visit adapter and both history readers execute verbatim.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def section(path, start, end):
    source = (ROOT / path).read_text()
    return start + source.split(start, 1)[1].split(end, 1)[0]


history = section('SAV-E/Services/SaveDoodleHomeCatalog.swift',
                  '@MainActor\nfinal class SaveDoodleVisitStore', '/// Only Home\'s Collected')
adapter = section('SAV-E/Views/Map/SavvyMapPhotoPins.swift',
                  '@MainActor\nfinal class SavvyMapVisitStore', '// MARK: - Card session')
passport = section('SAV-E/Views/Profile/SaveDoodlePassportCatalog.swift',
                   'enum SavePassportStampRank:', 'enum SaveDoodleStickerKind:')
update = section('SAV-E/ViewModels/MapViewModel.swift',
                 '    func updatePlace(_ place: Place) async throws {',
                 '    /// Park the attempted PATCH')
source = r'''
import Foundation
import Combine

enum PlaceStatus: String { case wantToGo, visited }
struct Place: Equatable { var id = UUID(); var status: PlaceStatus = .wantToGo }
enum ReviewCandidateError: Error { case sessionChangedAfterCommit }
struct SavePlaceLimitError: Error {}
struct Offline: Error {}
@MainActor final class Auth { var currentUserId: String? = "owner"; var sessionGeneration = 1 }
@MainActor final class Network {
    var action: () async throws -> Void = {}
    func updatePlace(_ place: Place, previous: Place) async throws { try await action() }
}
@MainActor final class Vault {
    func saveConfirmedPlace(_ place: Place, ownerSubject: String?) throws -> Place { place }
}
@MainActor final class SavePassportFieldStreakStore {
    static let shared = SavePassportFieldStreakStore()
    static func countsVisit(previous: PlaceStatus, updated: PlaceStatus) -> Bool { false }
    func recordFieldAction() {}
}
@MainActor final class Model {
    var places: [Place] = []
    var selectedPlace: Place?
    let authService = Auth()
    let supabaseService = Network()
    let saveLocalVaultService = Vault()
    var usesRemotePersistence = true
    func mirrorToLocalVault(_ place: Place, startedBy owner: String?, generation: Int) throws {
        guard authService.currentUserId == owner, authService.sessionGeneration == generation else {
            throw ReviewCandidateError.sessionChangedAfterCommit
        }
    }
    func parkPlaceAfterPatchCap(_ place: Place, startedBy owner: String?, generation: Int) throws {}
''' + update + '\n}\n' + history + adapter + passport + r'''
@main struct Check {
    @MainActor static func main() async throws {
        let suite = "save.photo-map.host.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavvyMapVisitStore(defaults: defaults)
        let passport = SavePassportVisitStore(defaults: defaults)
        let model = Model()
        let original = Place()
        model.places = [original]
        model.selectedPlace = original
        var visited = original; visited.status = .visited
        let owner = model.authService.currentUserId
        let generation = model.authService.sessionGeneration
        func current() -> Bool {
            model.authService.currentUserId == owner && model.authService.sessionGeneration == generation
        }
        model.supabaseService.action = { await Task.yield(); throw Offline() }
        do {
            try await store.recordPersistedVisit(placeID: original.id, isCurrent: current) {
                try await model.updatePlace(visited)
            }
            preconditionFailure("Failed persistence accepted")
        } catch is Offline {}
        precondition(model.places == [original] && model.selectedPlace == original)
        precondition(passport.count(for: original.id) == 0 && store.visits(for: original.id).isEmpty)

        // Same owner but new generation is still stale; its catch cannot
        // restore the previous account's row into the replacement collection.
        let replacement = Place()
        model.supabaseService.action = {
            await Task.yield()
            model.authService.sessionGeneration += 1
            model.places = [replacement]
            model.selectedPlace = replacement
        }
        do {
            try await store.recordPersistedVisit(placeID: original.id, isCurrent: current) {
                try await model.updatePlace(visited)
            }
            preconditionFailure("Stale update accepted")
        } catch is ReviewCandidateError {}
        precondition(model.places == [replacement] && model.selectedPlace == replacement)
        precondition(passport.count(for: original.id) == 0)

        // Even a persistence closure that returns normally after a session
        // change must not append local truth.
        var active = true
        do {
            try await store.recordPersistedVisit(placeID: original.id, isCurrent: { active }) {
                await Task.yield(); active = false
            }
            preconditionFailure("Stale completion accepted")
        } catch is CancellationError {}
        precondition(passport.count(for: original.id) == 0)

        model.authService.sessionGeneration = generation
        model.places = [original]; model.selectedPlace = original
        model.supabaseService.action = { await Task.yield() }
        for _ in 0..<3 {
            try await store.recordPersistedVisit(placeID: original.id, isCurrent: current) {
                try await model.updatePlace(visited)
            }
        }
        precondition(model.places == [visited] && model.selectedPlace == visited)
        precondition(passport.count(for: original.id) == 1)
        precondition(passport.recordVisit(for: original.id) == 1)
        precondition(SavvyMapVisitStore(defaults: defaults).visitCount(for: original.id, fallbackVisited: false) == 1)

        // Missing rows cannot silently authorize history.
        model.places = []
        do { try await model.updatePlace(visited); preconditionFailure("Missing row accepted") }
        catch is CancellationError {}

        let legacyID = UUID()
        let stamps = [1_700_000_000.0, 1_700_000_001.0, 1_700_086_400.0]
        defaults.set([legacyID.uuidString: stamps], forKey: "legacy")
        let legacyStore = SavvyMapVisitStore(defaults: defaults, key: "legacy")
        precondition(legacyStore.visitCount(for: legacyID, fallbackVisited: false) == 2)
        precondition(defaults.dictionary(forKey: "legacy") as? [String: [Double]] == [legacyID.uuidString: stamps])
        let datedHistory = SaveDoodleVisitStore(defaults: defaults, now: { Date(timeIntervalSince1970: stamps.last!) })
        precondition(datedHistory.undoToday(for: legacyID))
        precondition(SavvyMapVisitStore(defaults: defaults, key: "legacy").visitCount(for: legacyID, fallbackVisited: false) == 1)
        print("PASS: actual updatePlace failure rollback, stale-session collection safety, stale-success fence, missing-row rejection, shared Passport daily dedup, non-destructive legacy import and undo/relaunch")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='save-photo-visits-') as directory:
    output = Path(directory)
    swift = output / 'Check.swift'
    swift.write_text(source)
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', str(swift),
                    '-o', str(output / 'check')], check=True)
    subprocess.run([str(output / 'check')], check=True)

#!/usr/bin/env python3
"""Execute real Clip intent storage/handoff and app confirmation coordination.

UIKit opening is injected; all journals use a temporary isolated defaults suite.
Native app model/session regression tests remain in SAVETests for canonical CI.
"""
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]

def section(source, start, end):
    return start + source.split(start, 1)[1].split(end, 1)[0]

clip = (ROOT / 'SAV-EClip/ClipSaveService.swift').read_text()
app = (ROOT / 'SAV-E/Models/PendingShareStore.swift').read_text()
pending = (ROOT / 'SAV-EClip/PendingShareStore.swift').read_text()
app_store = section(app, 'enum PendingShareStore {', '/// Always recompute')
app_store = app_store.replace('enum PendingShareStore {', 'enum AppPendingShareStore {', 1)
coordinator = section(app, '@MainActor\n@Observable\nfinal class ClipListHandoffAttempt', 'enum ClipListHandoff {')
counts = section(app, 'struct ClipListHandoffCounts:', '/// A Clip journal selects')
methods = section(app, '    func matchesIncomingPlace(', '\n}\n\nenum PendingShareStore')
selector = section(app, '    static func itemsToStamp(', '    static func stampList(')
service = section(clip, '@MainActor\nenum ClipSaveService {', '    private static func openInstalledApp(')
service += '''    private static func openInstalledApp(_ url: URL, completion: @escaping (Bool) -> Void) {
        preconditionFailure("Host regression must inject opening")
    }
}\n'''
draft = section(clip, 'struct ClipPlaceDraft:', '    static func from(place:') + '}\n'
outcome = section(clip, 'enum ClipSaveOutcome:', 'struct ClipPlaceDraft:')
planner = (ROOT / 'SAV-EClip/ClipListSavePlanner.swift').read_text()
suite = 'save.clip.host.' + str(uuid.uuid4())
source = 'import Foundation\nimport CoreLocation\nimport Observation\n' + pending + app_store + outcome + draft + planner
source += '''
@MainActor enum ClipFullApp { static var isInstalled: Bool { false } }
enum SaveSharedListPayload {
    static func shareCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "c" }?.value
    }
}
typealias SaveListItem = ClipListSaveItem
struct SaveCollaborativeList: Equatable { var id = UUID(); var items: [SaveListItem] }
extension PendingSharePayload {
''' + methods + '\n}\n' + '''
extension PendingConfirmedPlace {
    // Platform model projection only; selection and persistence algorithms are verbatim.
    func asListItem() -> SaveListItem {
        .init(name: name, address: address, latitude: latitude, longitude: longitude,
              category: category, rating: nil, note: nil, sourceURL: sourceURL, placeId: placeId)
    }
}
enum ClipListHandoff {
    static func shouldConfirmList(pending: PendingSharePayload?, incomingURL: URL) -> Bool {
        pending?.matchesIncomingList(url: incomingURL) == true
    }
''' + selector + '\n}\n' + counts + coordinator + service
source += r'''
struct Failure: Error {}
@main struct Check {
    @MainActor static func main() async throws {
        let defaults = UserDefaults(suiteName: PendingShareStore.suiteName)!
        defer { defaults.removePersistentDomain(forName: PendingShareStore.suiteName) }
        let url = URL(string: "https://sav-e-app.vercel.app/p/test")!
        let draft = ClipPlaceDraft(name: "Selected", address: "Taipei", latitude: 25.03, longitude: 121.56,
            category: "cafe", rating: 5, note: "sender private note", sourceURL: nil, placeId: "selected", friendShareCode: nil)
        let absent = await ClipSaveService.save(draft: draft, handoffURL: url, sender: nil, isInstalled: false,
            openURL: { _, _ in preconditionFailure("Absent app cannot open") })
        precondition(absent == .pending(1))
        let first = AppPendingShareStore.load()!
        precondition(first.confirmedPlaces?.count == 1 && first.confirmedPlaces?.first?.name == draft.name)
        let failedOpen = await ClipSaveService.save(draft: draft, handoffURL: url, sender: nil, isInstalled: true,
            openURL: { _, done in done(false) })
        precondition(failedOpen == .pending(1))
        let newer = AppPendingShareStore.load()!
        precondition(newer.invocationID != first.invocationID)
        precondition(!AppPendingShareStore.clear(ifUnchanged: first))
        precondition(AppPendingShareStore.load() == newer)
        let handedOff = await ClipSaveService.save(draft: draft, handoffURL: url, sender: nil, isInstalled: true,
            openURL: { _, done in done(true) })
        precondition(handedOff == .handedOff && AppPendingShareStore.load() != nil)

        let listURL = URL(string: "https://sav-e-app.vercel.app/list?c=selected")!
        let listOutcome = await ClipSaveService.saveList(drafts: [draft, draft], listId: nil,
            shareCode: "selected", handoffURL: listURL, sender: nil, isInstalled: false)
        precondition(listOutcome == .pending(1))
        let listJournal = AppPendingShareStore.load()!
        let extra = ClipListSaveItem(name: "Unselected live extra", address: "Osaka", latitude: 34, longitude: 135,
            category: "cafe", rating: nil, note: nil, sourceURL: nil, placeId: "extra")
        let selected = ClipListHandoff.itemsToStamp(pending: listJournal, incomingURL: listURL, liveItems: [extra])
        precondition(selected.count == 1 && selected.first?.name == draft.name)
        precondition(ClipListHandoff.itemsToStamp(pending: listJournal,
            incomingURL: URL(string: "https://sav-e-app.vercel.app/list?c=unrelated")!, liveItems: [extra]).isEmpty)

        let a = SaveCollaborativeList(items: selected)
        let b = SaveCollaborativeList(items: [extra])
        let coordinator = ClipListHandoffAttempt()
        var current: SaveCollaborativeList? = a
        var requests: [UUID] = []
        var acknowledgements = 0
        var failures = 0
        // Opening/dismissing a confirmation is a no-op: only runConfirmed writes.
        precondition(requests.isEmpty && AppPendingShareStore.load() == listJournal)
        await coordinator.runConfirmed(pending: { current }, save: { list in
            requests.append(list.id); await Task.yield(); throw Failure()
        }, succeeded: { _, _ in acknowledgements += 1 }, failed: { _ in failures += 1 })
        precondition(failures == 1 && acknowledgements == 0 && AppPendingShareStore.load() == listJournal)
        requests = []
        let counts = ClipListHandoffCounts(newlySaved: 1, alreadySaved: 0, overCap: 0, remaining: 49, limit: 50)
        await coordinator.runConfirmed(pending: { current }, save: { list in
            requests.append(list.id)
            await Task.yield()
            current = b
            return (list.items, counts)
        }, succeeded: { _, _ in acknowledgements += 1 }, failed: { _ in preconditionFailure() })
        precondition(requests == [a.id] && current == b && acknowledgements == 0)
        await coordinator.runConfirmed(pending: { current }, save: { list in
            requests.append(list.id); return (list.items, counts)
        }, succeeded: { list, _ in
            precondition(list == b); acknowledgements += 1; current = nil
        }, failed: { _ in preconditionFailure() })
        precondition(requests == [a.id, b.id] && acknowledgements == 1)
        precondition(AppPendingShareStore.clear(ifUnchanged: listJournal))
        precondition(AppPendingShareStore.load() == nil)
        // Old journals without invocationID remain readable.
        let legacy = Data(#"{"kind":"place","url":"https://example.com/p/legacy"}"#.utf8)
        defaults.set(legacy, forKey: PendingShareStore.key)
        precondition(AppPendingShareStore.load()?.invocationID == nil)
        print("PASS: Clip absent/open-failed/successful handoff retains durable intent; same-link newer invocation survives; selected snapshot excludes live extras; failed/cancelled confirmation retains journal; replacement requires separate tap; matching success clears; legacy journal decodes")
    }
}
'''
source = source.replace('"group.com.wanderly.app"', '"' + suite + '"')
with tempfile.TemporaryDirectory(prefix='save-clip-pending-') as directory:
    output = Path(directory)
    swift = output / 'Check.swift'
    swift.write_text(source)
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', str(swift), '-o', str(output / 'check')], check=True)
    subprocess.run([str(output / 'check')], check=True)

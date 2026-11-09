// Standalone macOS regression for the actual iMessage reader (no target/CI changes).
// From the repository root, choose task-owned output and module-cache paths:
// swiftc -module-cache-path "$TASK_HOST_CACHE" SAV-EiMessage/MessagesVaultReader.swift \
//   scripts/messages-vault-deletion-check/main.swift -o "$TASK_HOST_BINARY"
// "$TASK_HOST_BINARY"
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MessagesDeletionFixture-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let url = directory.appendingPathComponent("vault.json")
let receiptURL = url.appendingPathExtension("account-deletion.json")
let oldID = UUID(), aID = UUID(), bID = UUID(), laterID = UUID()
func row(_ id: UUID, _ title: String, _ owner: String?) -> [String: Any] {
    var result: [String: Any] = ["id": id.uuidString, "state": "confirmed_place", "title": title,
        "latitude": 25.0, "longitude": 121.0, "sourceText": "Private note", "evidence": ["Private clue"]]
    if let owner { result["ownerSubject"] = owner }
    return result
}
var rows = [row(oldID, "Old legacy", nil), row(aID, "A", "account-a"), row(bID, "B", "account-b"), row(laterID, "Later legacy", nil)]
func writeRows() throws { try JSONSerialization.data(withJSONObject: rows).write(to: url, options: .atomic) }
try writeRows()
func ids(_ owner: String?) -> Set<UUID> {
    Set(MessagesVaultReader.confirmedPlaces(vaultURL: url, currentOwner: owner).map(\.id))
}
expect(ids(nil) == [oldID, laterID], "old schema without receipt must remain compatible")
// P1 4365848914: owner captured before the coordinated read must not leak A after a switch.
let switched = Set(
    MessagesVaultReader.confirmedPlaces(
        vaultURL: url,
        currentOwner: "account-a",
        ownerProvider: { "account-b" }
    ).map(\.id)
)
expect(!switched.contains(aID), "A's places must not return after the owner switches to B")
expect(switched == [bID], "stable B after the switch retries once for B")
var ownerReads = 0
let discarded = MessagesVaultReader.confirmedPlaces(
    vaultURL: url,
    currentOwner: "account-a",
    ownerProvider: {
        ownerReads += 1
        return ownerReads == 1 ? "account-b" : "account-c"
    }
)
expect(discarded.isEmpty, "a second owner mismatch must discard")
let receipt: [String: Any] = ["id": UUID().uuidString, "owner": "account-a",
    "initialOwnerlessRecordIDs": [oldID.uuidString], "remoteOutcome": "awaitingRemoteResult"]
let receiptData = try JSONSerialization.data(withJSONObject: receipt)
try receiptData.write(to: receiptURL, options: .atomic)
expect(ids(nil) == [laterID], "pending legacy must stay hidden signed out")
expect(ids("account-a").isEmpty, "pending A rows must stay hidden")
expect(ids("account-b") == [bID], "B must remain visible to B")
rows[0]["ownerSubject"] = "account-b"
try writeRows()
expect(ids("account-b") == [oldID, bID], "independently stamped B row must survive A's initial legacy snapshot")
try Data("broken".utf8).write(to: receiptURL, options: .atomic)
expect(ids(nil).isEmpty && ids("account-b").isEmpty, "corrupt receipt must fail closed")
try FileManager.default.removeItem(at: receiptURL)
try FileManager.default.createDirectory(at: receiptURL, withIntermediateDirectories: false)
expect(ids(nil).isEmpty && ids("account-b").isEmpty, "unreadable receipt must fail closed")
try FileManager.default.removeItem(at: receiptURL)
try receiptData.write(to: receiptURL, options: .atomic)

rows[0].removeValue(forKey: "ownerSubject")
try writeRows()
// Exercise the actual reader while another coordinator holds the vault write.
// The writer changes both receipt and vault under that lock, exactly as cleanup does.
let readStarted = DispatchSemaphore(value: 0)
let readFinished = DispatchSemaphore(value: 0)
let coordinator = NSFileCoordinator(filePresenter: nil)
var coordinationError: NSError?
var writeError: Error?
coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { lockedURL in
    DispatchQueue.global().async {
        readStarted.signal()
        let observed = Set(MessagesVaultReader.confirmedPlaces(vaultURL: url, currentOwner: nil).map(\.id))
        expect(observed == [laterID], "concurrent reader must see a consistent quarantined or completed scope")
        readFinished.signal()
    }
    expect(readStarted.wait(timeout: .now() + 5) == .success, "reader did not start")
    do {
        let remaining = rows.filter {
            let id = $0["id"] as? String
            return id != aID.uuidString && id != oldID.uuidString
        }
        try JSONSerialization.data(withJSONObject: remaining).write(to: lockedURL, options: .atomic)
        try FileManager.default.removeItem(at: receiptURL)
    } catch { writeError = error }
}
if let coordinationError { throw coordinationError }
if let writeError { throw writeError }
expect(readFinished.wait(timeout: .now() + 5) == .success, "reader did not finish after coordinated write")
expect(ids(nil) == [laterID], "completed cleanup must not resurrect old legacy")
print("PASS: actual MessagesVaultReader legacy compatibility, restart quarantine, owner boundary, corrupt/unreadable receipt, coordinated concurrent read")

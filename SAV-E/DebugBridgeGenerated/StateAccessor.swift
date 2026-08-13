// AUTO-GENERATED — DO NOT EDIT. Regenerate with /ios-sync.
#if DEBUG
import Foundation
import DebugBridgeCore

@MainActor
enum DebugQAStateAccessor {
    private static func decodeSnapshotValue<T: Decodable>(_ value: Any, as type: T.Type) -> T? {
        guard JSONSerialization.isValidJSONObject(["value": value]),
              let data = try? JSONSerialization.data(withJSONObject: ["value": value]),
              let decoded = try? JSONDecoder().decode([String: T].self, from: data) else { return nil }
        return decoded["value"]
    }

    static func register(_ state: DebugQAState) {
        StateServer.shared.register(
            buildId: {
                let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                if let shortVersion, let bundleVersion { return "\(shortVersion) (\(bundleVersion))" }
                return shortVersion ?? bundleVersion ?? "unknown"
            }(),
            accessorHash: "7f4facd5252113c22cb00d1d8bc14ef149c659819683ad112297328202163e77",
            atomicRestore: { keys, apply in
                // Validate every key and value before assignment.
                // Successful assignments are sequential on MainActor.
                guard let raw0 = keys["qaRootTab"] else {
                    return .missingKey("qaRootTab")
                }
                guard let restored0 = Self.decodeSnapshotValue(raw0, as: String.self) else {
                    return .typeMismatch("qaRootTab")
                }
                guard let raw1 = keys["qaFullScreenKind"] else {
                    return .missingKey("qaFullScreenKind")
                }
                let restored1: String?
                if raw1 is NSNull {
                    restored1 = nil
                } else if let typed = Self.decodeSnapshotValue(raw1, as: String.self) {
                    restored1 = typed
                } else {
                    return .typeMismatch("qaFullScreenKind")
                }
                guard let raw2 = keys["qaIsRootSheetPresented"] else {
                    return .missingKey("qaIsRootSheetPresented")
                }
                guard let restored2 = Self.decodeSnapshotValue(raw2, as: Bool.self) else {
                    return .typeMismatch("qaIsRootSheetPresented")
                }
                guard let raw3 = keys["qaIsMapPanelExpanded"] else {
                    return .missingKey("qaIsMapPanelExpanded")
                }
                guard let restored3 = Self.decodeSnapshotValue(raw3, as: Bool.self) else {
                    return .typeMismatch("qaIsMapPanelExpanded")
                }
                guard let raw4 = keys["qaRootPathDepth"] else {
                    return .missingKey("qaRootPathDepth")
                }
                guard let restored4 = Self.decodeSnapshotValue(raw4, as: Int.self) else {
                    return .typeMismatch("qaRootPathDepth")
                }
                guard let raw5 = keys["qaSavedPlaceCount"] else {
                    return .missingKey("qaSavedPlaceCount")
                }
                guard let restored5 = Self.decodeSnapshotValue(raw5, as: Int.self) else {
                    return .typeMismatch("qaSavedPlaceCount")
                }
                guard let raw6 = keys["qaReviewCandidateCount"] else {
                    return .missingKey("qaReviewCandidateCount")
                }
                guard let restored6 = Self.decodeSnapshotValue(raw6, as: Int.self) else {
                    return .typeMismatch("qaReviewCandidateCount")
                }
                guard let raw7 = keys["qaMapCandidateCount"] else {
                    return .missingKey("qaMapCandidateCount")
                }
                guard let restored7 = Self.decodeSnapshotValue(raw7, as: Int.self) else {
                    return .typeMismatch("qaMapCandidateCount")
                }
                guard let raw8 = keys["qaHasIncomingReceipt"] else {
                    return .missingKey("qaHasIncomingReceipt")
                }
                guard let restored8 = Self.decodeSnapshotValue(raw8, as: Bool.self) else {
                    return .typeMismatch("qaHasIncomingReceipt")
                }
                if apply {
                    state.qaRootTab = restored0
                    state.qaFullScreenKind = restored1
                    state.qaIsRootSheetPresented = restored2
                    state.qaIsMapPanelExpanded = restored3
                    state.qaRootPathDepth = restored4
                    state.qaSavedPlaceCount = restored5
                    state.qaReviewCandidateCount = restored6
                    state.qaMapCandidateCount = restored7
                    state.qaHasIncomingReceipt = restored8
                }
                return .ok
            }
        )
        StateServer.shared.registerAccessor(
            key: "qaRootTab",
            type: "String",
            read: { state.qaRootTab as Any? },
            write: { value in
                guard let typed = Self.decodeSnapshotValue(value, as: String.self) else { return false }
                state.qaRootTab = typed
                return true
            }
        )
        StateServer.shared.registerAccessor(
            key: "qaFullScreenKind",
            type: "String?",
            read: {
                guard let value = state.qaFullScreenKind else { return NSNull() }
                return value as Any
            },
            write: { value in
                if value is NSNull {
                    state.qaFullScreenKind = nil
                    return true
                }
                guard let typed = Self.decodeSnapshotValue(value, as: String.self) else { return false }
                state.qaFullScreenKind = typed
                return true
            }
        )
        StateServer.shared.registerAccessor(
            key: "qaIsRootSheetPresented",
            type: "Bool",
            read: { state.qaIsRootSheetPresented as Any? },
            write: { value in
                guard let typed = Self.decodeSnapshotValue(value, as: Bool.self) else { return false }
                state.qaIsRootSheetPresented = typed
                return true
            }
        )
        StateServer.shared.registerAccessor(
            key: "qaIsMapPanelExpanded",
            type: "Bool",
            read: { state.qaIsMapPanelExpanded as Any? },
            write: { value in
                guard let typed = Self.decodeSnapshotValue(value, as: Bool.self) else { return false }
                state.qaIsMapPanelExpanded = typed
                return true
            }
        )
        StateServer.shared.registerAccessor(
            key: "qaRootPathDepth",
            type: "Int",
            read: { state.qaRootPathDepth as Any? },
            write: { value in
                guard let typed = Self.decodeSnapshotValue(value, as: Int.self) else { return false }
                state.qaRootPathDepth = typed
                return true
            }
        )
        StateServer.shared.registerAccessor(
            key: "qaSavedPlaceCount",
            type: "Int",
            read: { state.qaSavedPlaceCount as Any? },
            write: { value in
                guard let typed = Self.decodeSnapshotValue(value, as: Int.self) else { return false }
                state.qaSavedPlaceCount = typed
                return true
            }
        )
        StateServer.shared.registerAccessor(
            key: "qaReviewCandidateCount",
            type: "Int",
            read: { state.qaReviewCandidateCount as Any? },
            write: { value in
                guard let typed = Self.decodeSnapshotValue(value, as: Int.self) else { return false }
                state.qaReviewCandidateCount = typed
                return true
            }
        )
        StateServer.shared.registerAccessor(
            key: "qaMapCandidateCount",
            type: "Int",
            read: { state.qaMapCandidateCount as Any? },
            write: { value in
                guard let typed = Self.decodeSnapshotValue(value, as: Int.self) else { return false }
                state.qaMapCandidateCount = typed
                return true
            }
        )
        StateServer.shared.registerAccessor(
            key: "qaHasIncomingReceipt",
            type: "Bool",
            read: { state.qaHasIncomingReceipt as Any? },
            write: { value in
                guard let typed = Self.decodeSnapshotValue(value, as: Bool.self) else { return false }
                state.qaHasIncomingReceipt = typed
                return true
            }
        )
    }
}

#endif

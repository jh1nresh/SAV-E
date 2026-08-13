#if DEBUG

import Observation

/// Non-sensitive live state exposed only to the local iOS QA bridge.
/// These values mirror navigation state; restoring a snapshot never changes
/// product data, authentication, saved places, or private clue contents.
@MainActor
@Observable
final class DebugQAState {
    static let shared = DebugQAState()

    // @Snapshotable
    var qaRootTab: String = "home"

    // @Snapshotable
    var qaFullScreenKind: String? = nil

    // @Snapshotable
    var qaIsRootSheetPresented: Bool = false

    // @Snapshotable
    var qaIsMapPanelExpanded: Bool = false

    // @Snapshotable
    var qaRootPathDepth: Int = 0

    // @Snapshotable
    var qaSavedPlaceCount: Int = 0

    // @Snapshotable
    var qaReviewCandidateCount: Int = 0

    // @Snapshotable
    var qaMapCandidateCount: Int = 0

    // @Snapshotable
    var qaHasIncomingReceipt: Bool = false

    private init() {}
}

#endif

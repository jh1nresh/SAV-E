import Foundation

enum SaveSearchObjectType: String, Codable, CaseIterable, Hashable {
    case savedPlace = "saved_place"
    case pendingCandidate = "pending_candidate"
    case sourceOnlyClue = "source_only_clue"
    case triedMemory = "tried_memory"
    case review = "review"
    case tripStop = "trip_stop"
    case mapVisibleUnsavedPlace = "map_visible_unsaved_place"
    case newRecommendation = "new_recommendation"

    var displayName: String {
        switch self {
        case .savedPlace: return "Map Stamp"
        case .pendingCandidate: return "Review Candidate"
        case .sourceOnlyClue: return "Clue"
        case .triedMemory: return "Visited Map Stamp"
        case .review: return "Private review"
        case .tripStop: return "Trip stop"
        case .mapVisibleUnsavedPlace: return "Not saved yet"
        case .newRecommendation: return "Recommendation"
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .savedPlace: return language.localized(english: "Map Stamp", traditionalChinese: "地圖章")
        case .pendingCandidate: return language.localized(english: "Review Candidate", traditionalChinese: "待確認地點")
        case .sourceOnlyClue: return language.localized(english: "Clue", traditionalChinese: "線索")
        case .triedMemory: return language.localized(english: "Visited Map Stamp", traditionalChinese: "去過的地圖章")
        case .review: return language.localized(english: "Private review", traditionalChinese: "私人評論")
        case .tripStop: return language.localized(english: "Trip stop", traditionalChinese: "行程地點")
        case .mapVisibleUnsavedPlace: return language.localized(english: "Not saved yet", traditionalChinese: "尚未保存")
        case .newRecommendation: return language.localized(english: "Recommendation", traditionalChinese: "推薦")
        }
    }
}

enum SaveSearchPrimaryAction: String, Codable, Hashable {
    case openSource = "open_source"
    case runRecovery = "run_recovery"
    case savePlace = "save_place"
    case confirmMapStamp = "confirm_map_stamp"
    case planAround = "plan_around"
    case addToTrip = "add_to_trip"
    case markTried = "mark_tried"
    case addReview = "add_review"
    case addProof = "add_proof"
    case showNearby = "show_nearby"
    case recommendOrder = "recommend_order"
    case addNote = "add_note"
    case saveClue = "save_clue"
    case none = "none"

    var displayName: String {
        switch self {
        case .openSource: return "Open source"
        case .runRecovery: return "Find exact place"
        case .savePlace: return "Save this place"
        case .confirmMapStamp: return "Confirm Map Stamp"
        case .planAround: return "Plan around this"
        case .addToTrip: return "Add to trip"
        case .markTried: return "Mark as tried"
        case .addReview: return "Add private review"
        case .addProof: return "Add proof"
        case .showNearby: return "Show nearby"
        case .recommendOrder: return "What should I order?"
        case .addNote: return "Add note"
        case .saveClue: return "Save as clue"
        case .none: return "No action"
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .openSource: return language.localized(english: "Open source", traditionalChinese: "打開來源")
        case .runRecovery: return language.localized(english: "Find exact place", traditionalChinese: "找出精確地點")
        case .savePlace: return language.localized(english: "Save this place", traditionalChinese: "保存這個地點")
        case .confirmMapStamp: return language.localized(english: "Confirm Map Stamp", traditionalChinese: "確認成地圖章")
        case .planAround: return language.localized(english: "Plan around this", traditionalChinese: "用這裡規劃")
        case .addToTrip: return language.localized(english: "Add to trip", traditionalChinese: "加入行程")
        case .markTried: return language.localized(english: "Mark as tried", traditionalChinese: "標記為去過")
        case .addReview: return language.localized(english: "Add private review", traditionalChinese: "新增私人評論")
        case .addProof: return language.localized(english: "Add proof", traditionalChinese: "新增憑證")
        case .showNearby: return language.localized(english: "Show nearby", traditionalChinese: "顯示附近")
        case .recommendOrder: return language.localized(english: "What should I order?", traditionalChinese: "我該點什麼？")
        case .addNote: return language.localized(english: "Add note", traditionalChinese: "新增筆記")
        case .saveClue: return language.localized(english: "Save as clue", traditionalChinese: "保存成線索")
        case .none: return language.localized(english: "No action", traditionalChinese: "沒有動作")
        }
    }

    var systemImage: String {
        switch self {
        case .openSource: return "link"
        case .runRecovery: return "sparkle.magnifyingglass"
        case .savePlace: return "bookmark.badge.plus"
        case .confirmMapStamp: return "checkmark.seal"
        case .planAround: return "wand.and.stars"
        case .addToTrip: return "plus.square.on.square"
        case .markTried: return "checkmark.seal"
        case .addReview: return "text.bubble"
        case .addProof: return "receipt"
        case .showNearby: return "location.magnifyingglass"
        case .recommendOrder: return "fork.knife"
        case .addNote: return "note.text"
        case .saveClue: return "tray.and.arrow.down"
        case .none: return "circle"
        }
    }
}

struct SaveAgentDrawerAction: Identifiable, Hashable {
    var kind: SaveSearchPrimaryAction
    var label: String
    var systemImage: String

    var id: SaveSearchPrimaryAction { kind }

    init(kind: SaveSearchPrimaryAction, label: String? = nil) {
        self.kind = kind
        self.label = label ?? kind.displayName
        self.systemImage = kind.systemImage
    }

    init(resolution: SavePlaceActionResolution) {
        self.kind = resolution.kind
        self.label = resolution.title
        self.systemImage = resolution.systemImage
    }
}

struct SaveAgentActionDrawerModel: Hashable {
    var heading: String
    var contextLine: String
    var primaryAction: SaveAgentDrawerAction
    var secondaryActions: [SaveAgentDrawerAction]
    var evidenceSummary: String
    var missingInfo: [String]

    init(result: SaveSearchResult) {
        heading = Self.heading(for: result)
        contextLine = Self.contextLine(for: result)
        primaryAction = SaveAgentDrawerAction(resolution: SavePlaceActionResolution(result: result))
        secondaryActions = Self.secondaryActions(for: result, excluding: primaryAction.kind)
        evidenceSummary = Self.evidenceSummary(for: result)
        missingInfo = result.missingInfo
    }

    private static func heading(for result: SaveSearchResult) -> String {
        switch result.objectType {
        case .sourceOnlyClue: return "Source clue"
        case .pendingCandidate: return "Review before stamping"
        case .mapVisibleUnsavedPlace: return "Not saved yet"
        case .savedPlace: return "Saved to your place memory"
        case .triedMemory: return "Update visited Map Stamp"
        case .review: return "Upgrade review proof"
        case .tripStop: return "Use trip stop"
        case .newRecommendation: return "Recommendation"
        }
    }

    private static func contextLine(for result: SaveSearchResult) -> String {
        switch result.objectType {
        case .sourceOnlyClue:
            return "SAV-E found a source, but not enough proof for a place yet."
        case .pendingCandidate:
            return "SAV-E found a likely place. Review the evidence before stamping it to your map."
        case .mapVisibleUnsavedPlace:
            return "This is a map-visible suggestion, not a saved memory yet."
        case .savedPlace:
            return "Ask what to order, plan around it, or add private notes later."
        case .triedMemory:
            return "Add private notes or proof to this visited Map Stamp."
        case .review:
            return "Keep the review private by default and add proof only when useful."
        case .tripStop:
            return "Reuse this stop in a route or guide."
        case .newRecommendation:
            return "Recommendations are contextual answers; choose a place before saving anything."
        }
    }

    private static func secondaryActions(for result: SaveSearchResult, excluding primary: SaveSearchPrimaryAction) -> [SaveAgentDrawerAction] {
        var actions: [SaveSearchPrimaryAction] = []

        switch result.objectType {
        case .sourceOnlyClue:
            actions = [.openSource, .addNote, .saveClue]
        case .pendingCandidate:
            actions = [.openSource, .runRecovery]
        case .mapVisibleUnsavedPlace:
            actions = [.planAround, .openSource, .showNearby]
        case .savedPlace:
            actions = [.planAround, .addNote, .openSource, .addToTrip, .markTried]
        case .triedMemory:
            actions = [.addProof, .planAround, .addToTrip]
        case .review:
            actions = [.openSource, .planAround]
        case .tripStop:
            actions = [.addToTrip, .showNearby]
        case .newRecommendation:
            actions = []
        }

        if !hasValidHTTPSourceURL(result.sourceURL) {
            actions.removeAll { $0 == .openSource }
        }
        actions.removeAll { $0 == primary || $0 == .none }

        var seen = Set<SaveSearchPrimaryAction>()
        return actions.compactMap { action in
            guard seen.insert(action).inserted else { return nil }
            return SaveAgentDrawerAction(kind: action)
        }
    }

    private static func hasValidHTTPSourceURL(_ sourceURL: String?) -> Bool {
        guard
            let rawValue = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            let url = URL(string: rawValue),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            url.host?.isEmpty == false
        else {
            return false
        }
        return true
    }

    private static func evidenceSummary(for result: SaveSearchResult) -> String {
        if !result.missingInfo.isEmpty {
            return "Missing: \(result.missingInfo.prefix(3).joined(separator: ", "))"
        }
        if result.objectType == .mapVisibleUnsavedPlace {
            return "Evidence: \(result.evidence.first ?? "Visible on map; not saved yet")"
        }
        if let sourcePlatform = result.sourcePlatform {
            return "Evidence: \(sourcePlatform.displayName) source linked"
        }
        if let first = result.evidence.first {
            return "Evidence: \(first)"
        }
        return "Evidence: no source attached yet"
    }
}

struct SavePlaceActionResolution: Hashable {
    var kind: SaveSearchPrimaryAction
    var title: String
    var systemImage: String

    init(kind: SaveSearchPrimaryAction) {
        self.kind = kind
        title = kind.displayName
        systemImage = kind.systemImage
    }

    init(result: SaveSearchResult) {
        self.init(kind: Self.primaryAction(for: result))
    }

    init(candidate: PlaceReviewCandidate) {
        self.init(kind: candidate.hasReliableCoordinates ? .confirmMapStamp : .runRecovery)
    }

    init(place: Place) {
        self.init(kind: place.status == .visited ? .addReview : .recommendOrder)
    }

    init(mapCandidate: SaveMapCandidate) {
        self.init(kind: .savePlace)
    }

    var confirmsMapStamp: Bool {
        kind == .confirmMapStamp
    }

    private static func primaryAction(for result: SaveSearchResult) -> SaveSearchPrimaryAction {
        switch result.objectType {
        case .sourceOnlyClue:
            return .runRecovery
        case .pendingCandidate:
            // Pending candidates stay in recovery unless the service marks them map-ready.
            if result.primaryAction == .confirmMapStamp {
                return .confirmMapStamp
            }
            return .runRecovery
        case .mapVisibleUnsavedPlace:
            return .savePlace
        case .savedPlace:
            return .recommendOrder
        case .tripStop:
            return .planAround
        case .triedMemory:
            return .addReview
        case .review:
            return .addProof
        case .newRecommendation:
            return result.primaryAction
        }
    }
}

enum SavePlaceMemoryState: Equatable {
    case clue
    case reviewCandidate
    case unsavedMapCandidate
    case mapStamp
    case menuOrderDraft
    case actionReceipt
}

struct SavePlaceDrawerPresentation: Equatable {
    var state: SavePlaceMemoryState
    var eyebrow: String
    var title: String
    var contextLine: String
    var trustLine: String
    var primaryActionTitle: String
    var primaryActionSystemImage: String
    var secondaryActionTitles: [String]

    init(
        state: SavePlaceMemoryState,
        eyebrow: String,
        title: String,
        contextLine: String,
        trustLine: String,
        primaryActionTitle: String,
        primaryActionSystemImage: String,
        secondaryActionTitles: [String]
    ) {
        self.state = state
        self.eyebrow = eyebrow
        self.title = title
        self.contextLine = contextLine
        self.trustLine = trustLine
        self.primaryActionTitle = primaryActionTitle
        self.primaryActionSystemImage = primaryActionSystemImage
        self.secondaryActionTitles = secondaryActionTitles
    }

    private static func primaryActionFields(
        _ resolution: SavePlaceActionResolution
    ) -> (title: String, systemImage: String) {
        (resolution.title, resolution.systemImage)
    }

    static func clue(
        title: String,
        contextLine: String,
        trustLine: String = "SAV-E found a source, but not enough proof for a place yet."
    ) -> SavePlaceDrawerPresentation {
        let primary = primaryActionFields(SavePlaceActionResolution(kind: .runRecovery))
        return SavePlaceDrawerPresentation(
            state: .clue,
            eyebrow: "Clue · Needs exact place",
            title: title,
            contextLine: contextLine,
            trustLine: trustLine,
            primaryActionTitle: primary.title,
            primaryActionSystemImage: primary.systemImage,
            secondaryActionTitles: ["View source", "Add note", "Save as clue"]
        )
    }

    static func reviewCandidate(
        title: String,
        contextLine: String,
        trustLine: String = "SAV-E found a likely place. Review the evidence before stamping it to your map."
    ) -> SavePlaceDrawerPresentation {
        let primary = primaryActionFields(SavePlaceActionResolution(kind: .confirmMapStamp))
        return SavePlaceDrawerPresentation(
            state: .reviewCandidate,
            eyebrow: "Review Candidate · Check before saving",
            title: title,
            contextLine: contextLine,
            trustLine: trustLine,
            primaryActionTitle: primary.title,
            primaryActionSystemImage: primary.systemImage,
            secondaryActionTitles: ["Save", "Reject", "View source"]
        )
    }

    static func unsavedMapCandidate(
        title: String,
        contextLine: String,
        trustLine: String = "Public discovery result, not one of your SAV-E memories yet."
    ) -> SavePlaceDrawerPresentation {
        let primary = primaryActionFields(SavePlaceActionResolution(kind: .savePlace))
        return SavePlaceDrawerPresentation(
            state: .unsavedMapCandidate,
            eyebrow: "Public discovery · Not saved yet",
            title: title,
            contextLine: contextLine,
            trustLine: trustLine,
            primaryActionTitle: primary.title,
            primaryActionSystemImage: primary.systemImage,
            secondaryActionTitles: ["Maps"]
        )
    }

    static func mapStamp(
        title: String,
        contextLine: String,
        trustLine: String = "Saved to your place memory."
    ) -> SavePlaceDrawerPresentation {
        let primary = primaryActionFields(SavePlaceActionResolution(kind: .recommendOrder))
        return SavePlaceDrawerPresentation(
            state: .mapStamp,
            eyebrow: "Map Stamp · From your SAV-E",
            title: title,
            contextLine: contextLine,
            trustLine: trustLine,
            primaryActionTitle: primary.title,
            primaryActionSystemImage: primary.systemImage,
            secondaryActionTitles: ["Plan around this", "Add private note", "Share SAV-E Card", "Edit memory"]
        )
    }

    static func menuOrderDraft(
        title: String,
        contextLine: String,
        trustLine: String = "SAV-E can turn this place memory into an order idea before you go."
    ) -> SavePlaceDrawerPresentation {
        SavePlaceDrawerPresentation(
            state: .menuOrderDraft,
            eyebrow: "Order draft · From your SAV-E",
            title: title,
            contextLine: contextLine,
            trustLine: trustLine,
            primaryActionTitle: "Draft order idea",
            primaryActionSystemImage: "fork.knife.circle",
            secondaryActionTitles: ["View place memory", "Add private note", "Share SAV-E Card"]
        )
    }

    static func actionReceipt(
        title: String,
        contextLine: String,
        trustLine: String = "Tried memory or proof attached."
    ) -> SavePlaceDrawerPresentation {
        let primary = primaryActionFields(SavePlaceActionResolution(kind: .addReview))
        return SavePlaceDrawerPresentation(
            state: .actionReceipt,
            eyebrow: "Action / Receipt · Proof attached",
            title: title,
            contextLine: contextLine,
            trustLine: trustLine,
            primaryActionTitle: primary.title,
            primaryActionSystemImage: primary.systemImage,
            secondaryActionTitles: ["View receipt", "Use again", "More"]
        )
    }

    init(place: Place) {
        switch place.status {
        case .visited:
            self = .actionReceipt(
                title: place.name,
                contextLine: "\(place.category.displayName) · Tried memory",
                trustLine: "Saved place you have marked as tried."
            )
        case .wantToGo:
            self = .mapStamp(
                title: place.name,
                contextLine: "\(place.category.displayName) · Saved memory"
            )
        }
    }

    init(reviewCandidate candidate: PlaceReviewCandidate) {
        if candidate.hasReliableCoordinates {
            self = .reviewCandidate(
                title: candidate.name,
                contextLine: candidate.address.isEmpty ? "Likely match" : candidate.address
            )
        } else {
            self = .clue(
                title: candidate.name,
                contextLine: candidate.city ?? "Source clue"
            )
        }
    }

    init(mapCandidate candidate: SaveMapCandidate) {
        var parts = [candidate.category?.displayName ?? "Place", "Map search"]
        if let distanceLabel = candidate.distanceLabel {
            parts.append(distanceLabel)
        }
        self = .unsavedMapCandidate(
            title: candidate.title,
            contextLine: parts.joined(separator: " · ")
        )
    }
}

struct SaveEvidenceDrawerModel: Hashable {
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var provenanceLabel: String?
    var confidenceLabel: String
    var evidenceAtoms: [SaveEvidenceAtom]
    var missingFields: [String]
    var recoveryQueries: [String]
    var candidateExplanation: String?

    init(result: SaveSearchResult) {
        sourceURL = result.sourceURL
        sourcePlatform = result.sourcePlatform
        provenanceLabel = Self.provenanceLabel(for: result)
        confidenceLabel = Self.confidenceLabel(for: result)
        evidenceAtoms = Self.evidenceAtoms(for: result)
        missingFields = result.missingInfo
        recoveryQueries = result.recoveryQueries
        candidateExplanation = Self.candidateExplanation(for: result)
    }

    private static func provenanceLabel(for result: SaveSearchResult) -> String? {
        switch result.objectType {
        case .sourceOnlyClue:
            return result.sourcePlatform.map { "Clue from \($0.displayName)" } ?? "Source Clue"
        case .pendingCandidate:
            return "Review Candidate; confirm before Map Stamp"
        case .mapVisibleUnsavedPlace:
            return "Unsaved candidate; not a Map Stamp"
        case .savedPlace:
            return "Map Stamp saved in SAV-E"
        case .triedMemory:
            return "Visited Map Stamp"
        case .review:
            return "Private review"
        case .tripStop:
            return "Trip stop"
        case .newRecommendation:
            return "Recommendation; no saved memory"
        }
    }

    private static func confidenceLabel(for result: SaveSearchResult) -> String {
        if let confidence = result.confidence {
            return "\(Int((confidence * 100).rounded()))% confidence"
        }
        switch result.objectType {
        case .sourceOnlyClue:
            return "Exact place unconfirmed"
        case .pendingCandidate:
            return "Candidate needs review"
        case .mapVisibleUnsavedPlace:
            return "Map evidence present"
        case .savedPlace:
            return "Map Stamp"
        case .triedMemory, .tripStop:
            return "Map Stamp"
        case .review:
            return "Review evidence"
        case .newRecommendation:
            return "Unsaved recommendation"
        }
    }

    private static func candidateExplanation(for result: SaveSearchResult) -> String? {
        switch result.objectType {
        case .sourceOnlyClue:
            return "SAV-E is preserving the source clue without creating a Map Stamp."
        case .pendingCandidate:
            return "This can become a Map Stamp only after the place evidence is confirmed."
        case .mapVisibleUnsavedPlace:
            return "This is an unsaved candidate, not a Map Stamp yet."
        case .savedPlace:
            return "This Map Stamp is already saved in SAV-E."
        case .newRecommendation:
            return "This is a recommendation, not a saved memory. Choose a concrete place first."
        case .triedMemory, .review, .tripStop:
            return nil
        }
    }

    private static func evidenceAtoms(for result: SaveSearchResult) -> [SaveEvidenceAtom] {
        var atoms: [SaveEvidenceAtom] = []

        if let sourceURL = result.sourceURL, !sourceURL.isEmpty {
            atoms.append(SaveEvidenceAtom(kind: .sourceURL, label: "Source", value: sourceURL))
        } else if result.objectType == .mapVisibleUnsavedPlace {
            atoms.append(SaveEvidenceAtom(kind: .sourceURL, label: "Source", value: "Map result"))
        }

        if let sourcePlatform = result.sourcePlatform {
            atoms.append(SaveEvidenceAtom(kind: .sourceURL, label: "Platform", value: sourcePlatform.displayName))
        }
        if !result.subtitle.isEmpty, result.objectType != .sourceOnlyClue {
            let label = result.objectType == .mapVisibleUnsavedPlace ? "Map label" : "Address"
            atoms.append(SaveEvidenceAtom(kind: .address, label: label, value: result.subtitle))
        }
        if result.latitude != nil, result.longitude != nil {
            atoms.append(SaveEvidenceAtom(kind: .coordinates, label: "Coordinates", value: "present"))
        }
        if let rating = result.rating {
            atoms.append(SaveEvidenceAtom(kind: .rating, label: "Rating", value: String(format: "%.1f", rating)))
        }
        if let reviewCount = result.reviewCount {
            atoms.append(SaveEvidenceAtom(kind: .reviewCount, label: "Reviews", value: "\(reviewCount)"))
        }
        if result.userState == .unsaved {
            atoms.append(SaveEvidenceAtom(kind: .receipt, label: "State", value: "Unsaved; not a Map Stamp"))
        } else if result.objectType == .savedPlace {
            atoms.append(SaveEvidenceAtom(kind: .receipt, label: "State", value: "Saved Map Stamp"))
        }

        for evidence in result.evidence {
            if let atom = SaveEvidenceAtom(evidenceLine: evidence) {
                atoms.append(atom)
            }
        }

        return Self.uniqueAtoms(atoms)
    }

    private static func uniqueAtoms(_ atoms: [SaveEvidenceAtom]) -> [SaveEvidenceAtom] {
        var seen = Set<String>()
        return atoms.filter { atom in
            let key = "\(atom.kind.rawValue)|\(atom.label)|\(atom.value)"
            return seen.insert(key).inserted
        }
    }
}

struct SaveEvidenceAtom: Identifiable, Hashable {
    var id: UUID
    var kind: SaveEvidenceAtomKind
    var label: String
    var value: String

    init(id: UUID = UUID(), kind: SaveEvidenceAtomKind, label: String, value: String) {
        self.id = id
        self.kind = kind
        self.label = label
        self.value = value
    }

    init?(evidenceLine: String) {
        let line = evidenceLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        let lowered = line.lowercased()
        if lowered.hasPrefix("source url:") || lowered.hasPrefix("source:") {
            self.init(kind: .sourceURL, label: "Source", value: Self.value(afterColonIn: line))
        } else if lowered.contains("caption") {
            self.init(kind: .caption, label: "Caption clue", value: line)
        } else if lowered.contains("creator") || lowered.contains("provenance") {
            self.init(kind: .creator, label: "Creator/provenance", value: line)
        } else if lowered.contains("venue handle") {
            self.init(kind: .venueHandle, label: "Venue handle", value: line)
        } else if lowered.contains("address") {
            self.init(kind: .address, label: "Address clue", value: line)
        } else if lowered.contains("coordinate") {
            self.init(kind: .coordinates, label: "Coordinates", value: line)
        } else if lowered.contains("rating") {
            self.init(kind: .rating, label: "Rating", value: line)
        } else if lowered.contains("review") {
            self.init(kind: .reviewCount, label: "Review count", value: line)
        } else if lowered.contains("receipt") {
            self.init(kind: .receipt, label: "Receipt", value: line)
        } else {
            self.init(kind: .userNote, label: "Evidence", value: line)
        }
    }

    private static func value(afterColonIn line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SaveEvidenceAtomKind: String, Hashable {
    case sourceURL
    case caption
    case creator
    case venueHandle
    case address
    case city
    case coordinates
    case rating
    case reviewCount
    case userNote
    case receipt
}

struct SaveMapCandidate: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var category: PlaceCategory?
    var rating: Double?
    var reviewCount: Int?
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var photoURL: String?
    var businessPhotoURLs: [String]?
    var distanceMeters: Double?
    var evidence: [String]
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        latitude: Double,
        longitude: Double,
        category: PlaceCategory? = nil,
        rating: Double? = nil,
        reviewCount: Int? = nil,
        sourceURL: String? = nil,
        sourcePlatform: SourcePlatform? = nil,
        photoURL: String? = nil,
        businessPhotoURLs: [String]? = nil,
        distanceMeters: Double? = nil,
        evidence: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.rating = rating
        self.reviewCount = reviewCount
        self.sourceURL = sourceURL
        self.sourcePlatform = sourcePlatform
        self.photoURL = photoURL
        self.businessPhotoURLs = businessPhotoURLs
        self.distanceMeters = distanceMeters
        self.evidence = evidence
        self.createdAt = createdAt
    }
}

extension SaveMapCandidate {
    var businessPhotoURLStrings: [String] {
        var values = businessPhotoURLs ?? []
        if let photoURL {
            values.insert(photoURL, at: 0)
        }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingDuplicates()
    }

    func matches(_ other: SaveMapCandidate) -> Bool {
        let nearby = abs(latitude - other.latitude) < 0.0008 &&
            abs(longitude - other.longitude) < 0.0008
        let sameName = title.localizedCaseInsensitiveCompare(other.title) == .orderedSame
        return sameName && nearby
    }

    var distanceLabel: String? {
        distanceMeters.map(Self.distanceLabel)
    }

    var shareSubject: String {
        "SAV-E Map Result: \(title)"
    }

    var saveShareURL: URL? {
        SharedPlaceData.from(candidate: self).toURL()
    }

    var shareText: String {
        var lines = [
            "SAV-E Map Result",
            title,
            subtitle
        ]

        if let category {
            lines.append("Category: \(category.displayName)")
        }
        if let rating {
            lines.append("Rating: \(String(format: "%.1f", rating))")
        }
        if let reviewCount {
            lines.append("Reviews: \(reviewCount)")
        }
        if let distanceLabel {
            lines.append("Distance: \(distanceLabel)")
        }
        if let sourceURL, !sourceURL.isEmpty {
            lines.append("Source: \(sourceURL)")
        }
        if let saveShareURL {
            lines.append("Open in SAV-E: \(saveShareURL.absoluteString)")
        }

        return lines.joined(separator: "\n")
    }

    var shareMessage: String {
        var parts = [subtitle]
        if let category {
            parts.append(category.displayName)
        }
        if let rating {
            parts.append(String(format: "%.1f stars", rating))
        }
        if let reviewCount {
            parts.append("\(reviewCount) reviews")
        }
        if let distanceLabel {
            parts.append(distanceLabel)
        }
        return parts.joined(separator: " · ")
    }

    var shareAreaLabel: String {
        let parts = subtitle
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 { return parts[parts.count - 2] }
        return parts.first ?? ""
    }

    var shareNote: String? {
        var parts: [String] = []
        if let rating {
            parts.append(String(format: "%.1f stars", rating))
        }
        if let reviewCount {
            parts.append("\(reviewCount) reviews")
        }
        if let distanceLabel {
            parts.append(distanceLabel)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var appleMapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: title),
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")
        ]
        return components?.url
    }

    private static func distanceLabel(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km away", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m away"
    }
}


struct FoodPlaceOrderAnalysis: Equatable {
    var title: String
    var message: String
    var citedEvidence: [String]
    var recommendedItems: [RecommendedItem]
    var placeID: String?
}

struct FoodPlaceAnalysisService {
    private let insightService: FoodPlaceInsightService

    init(insightService: FoodPlaceInsightService = FoodPlaceInsightService()) {
        self.insightService = insightService
    }

    func whatShouldIOrder(
        at place: Place,
        outputLanguage: AppLanguage = .english
    ) -> SaveAIResponse {
        let analysis = orderAnalysis(for: place, outputLanguage: outputLanguage)
        return SaveAIResponse(
            componentType: .message,
            title: analysis.title,
            placeIds: analysis.placeID.map { [$0] } ?? [],
            navigationPlaceId: analysis.placeID,
            transportMode: .walking,
            itineraryDays: [],
            messageText: analysis.message,
            mapAction: MapActionData(
                type: .focusRegion,
                placeIds: analysis.placeID.map { [$0] },
                lat: place.latitude,
                lng: place.longitude,
                span: 0.01
            ),
            aiMessage: analysis.message
        )
    }

    func orderAnalysis(
        for place: Place,
        outputLanguage: AppLanguage = .english
    ) -> FoodPlaceOrderAnalysis {
        guard let insight = insightService.insight(for: place) else {
            let message = outputLanguage.localized(
                english: "I do not have saved order evidence for \(place.name) yet, so I will not invent a dish. Add a saved note or source clue with the item you want SAV-E to remember.",
                traditionalChinese: "我目前沒有「\(place.name)」的已保存點餐證據，所以不會編造菜名。可以新增筆記或來源線索，讓 SAV-E 記住推薦品項。"
            )
            return FoodPlaceOrderAnalysis(
                title: outputLanguage.localized(english: "No saved order clue yet", traditionalChinese: "尚無已保存點餐線索"),
                message: message,
                citedEvidence: [],
                recommendedItems: [],
                placeID: place.id.uuidString
            )
        }
        return orderAnalysis(for: insight, placeID: place.id.uuidString, outputLanguage: outputLanguage)
    }

    func orderAnalysis(
        for insight: FoodPlaceInsight,
        placeID: String? = nil,
        outputLanguage: AppLanguage = .english
    ) -> FoodPlaceOrderAnalysis {
        let citedEvidence = groundedEvidence(from: insight)
        if !insight.recommendedItems.isEmpty {
            let items = insight.recommendedItems.prefix(3).map(\.displayText).joined(separator: ", ")
            let context = supportingContext(from: insight, outputLanguage: outputLanguage)
            let source = sourceLine(from: insight, outputLanguage: outputLanguage)
            let message = outputLanguage.localized(
                english: "Order \(items).\(context) This is based only on your saved SAV-E evidence\(source).",
                traditionalChinese: "可以點 \(items)。\(context) 這只根據你已保存的 SAV-E 證據\(source)。"
            )
            return FoodPlaceOrderAnalysis(
                title: outputLanguage.localized(english: "What to order at \(insight.title)", traditionalChinese: "在「\(insight.title)」點什麼"),
                message: message,
                citedEvidence: citedEvidence,
                recommendedItems: Array(insight.recommendedItems.prefix(3)),
                placeID: placeID
            )
        }

        let fallbackClue = firstNonDishClue(from: insight, outputLanguage: outputLanguage)
        let message = outputLanguage.localized(
            english: "I do not have a saved dish for \(insight.title) yet, so I will not invent a menu item.\(fallbackClue)",
            traditionalChinese: "我目前沒有「\(insight.title)」的已保存菜名，所以不會編造菜單品項。\(fallbackClue)"
        )
        return FoodPlaceOrderAnalysis(
            title: outputLanguage.localized(english: "No saved dish yet", traditionalChinese: "尚無已保存菜名"),
            message: message,
            citedEvidence: citedEvidence,
            recommendedItems: [],
            placeID: placeID
        )
    }

    private func groundedEvidence(from insight: FoodPlaceInsight) -> [String] {
        var evidence: [String] = []
        evidence.append(contentsOf: insight.recommendedItems.map { "Recommended item: \($0.displayText)" })
        evidence.append(contentsOf: insight.highlights.map { "Highlight: \($0)" })
        evidence.append(contentsOf: insight.vibeTags.map { "Vibe: \($0)" })
        evidence.append(contentsOf: insight.accessNotes.map { "Access: \($0)" })
        evidence.append(contentsOf: insight.evidence)
        return evidence.removingDuplicatesForFoodInsight()
    }

    private func supportingContext(from insight: FoodPlaceInsight, outputLanguage: AppLanguage) -> String {
        if let highlight = insight.highlights.first?.trimmingCharacters(in: .whitespacesAndNewlines), !highlight.isEmpty {
            return outputLanguage.localized(english: " Saved note: \(highlight).", traditionalChinese: " 已保存筆記：\(highlight)。")
        }
        if let vibe = insight.vibeTags.first?.trimmingCharacters(in: .whitespacesAndNewlines), !vibe.isEmpty {
            return outputLanguage.localized(english: " Saved vibe: \(vibe).", traditionalChinese: " 已保存氛圍：\(vibe)。")
        }
        return ""
    }

    private func sourceLine(from insight: FoodPlaceInsight, outputLanguage: AppLanguage) -> String {
        if let handle = insight.sourceHandle?.trimmingCharacters(in: .whitespacesAndNewlines), !handle.isEmpty {
            return outputLanguage.localized(english: " from @\(handle)", traditionalChinese: "，來源是 @\(handle)")
        }
        if insight.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return outputLanguage.localized(english: " from the saved source", traditionalChinese: "，來源是已保存連結")
        }
        return ""
    }

    private func firstNonDishClue(from insight: FoodPlaceInsight, outputLanguage: AppLanguage) -> String {
        if let highlight = insight.highlights.first?.trimmingCharacters(in: .whitespacesAndNewlines), !highlight.isEmpty {
            return outputLanguage.localized(english: " Saved clue: \(highlight).", traditionalChinese: " 已保存線索：\(highlight)。")
        }
        if let vibe = insight.vibeTags.first?.trimmingCharacters(in: .whitespacesAndNewlines), !vibe.isEmpty {
            return outputLanguage.localized(english: " Saved vibe: \(vibe).", traditionalChinese: " 已保存氛圍：\(vibe)。")
        }
        if let access = insight.accessNotes.first?.trimmingCharacters(in: .whitespacesAndNewlines), !access.isEmpty {
            return outputLanguage.localized(english: " Saved access note: \(access).", traditionalChinese: " 已保存交通/到訪線索：\(access)。")
        }
        return ""
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}

struct SavePlaceDraft: Hashable {
    var title: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var category: PlaceCategory?
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var evidence: [String]
    var externalRating: Double?
    var externalReviewCount: Int?
}

enum SavePlaceDraftError: LocalizedError {
    case notSaveableMapCandidate
    case missingCoordinates

    var errorDescription: String? {
        switch self {
        case .notSaveableMapCandidate:
            return "This result needs a concrete map place before it can be saved."
        case .missingCoordinates:
            return "This place needs coordinates before it can be saved as a map memory."
        }
    }
}

enum SaveSearchUserState: String, Codable, CaseIterable, Hashable {
    case wantToGo = "want_to_go"
    case waitingReview = "waiting_review"
    case sourceOnly = "source_only"
    case visited = "visited"
    case reviewed = "reviewed"
    case unsaved = "unsaved"

    var displayName: String {
        switch self {
        case .wantToGo: return "Saved"
        case .waitingReview: return "Needs review"
        case .sourceOnly: return "Needs one more clue"
        case .visited: return "Visited"
        case .reviewed: return "Reviewed"
        case .unsaved: return "Unsaved"
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .wantToGo: return language.localized(english: "Saved", traditionalChinese: "已保存")
        case .waitingReview: return language.localized(english: "Needs review", traditionalChinese: "需要確認")
        case .sourceOnly: return language.localized(english: "Needs one more clue", traditionalChinese: "還需要線索")
        case .visited: return language.localized(english: "Visited", traditionalChinese: "去過")
        case .reviewed: return language.localized(english: "Reviewed", traditionalChinese: "已評論")
        case .unsaved: return language.localized(english: "Unsaved", traditionalChinese: "未保存")
        }
    }
}

enum SaveReviewVisibility: String, Codable, Hashable {
    case privateOnly = "private"
    case shareableSnapshot = "shareable_snapshot"
}

enum SaveReceiptProofKind: String, Codable, Hashable {
    case sourceLink = "source_link"
    case mapConfirmed = "map_confirmed"
    case visitMarked = "visit_marked"
    case receiptCommitment = "receipt_commitment"
}

struct SaveReceiptProofRef: Codable, Hashable {
    var kind: SaveReceiptProofKind
    var label: String
    var url: String?
    var commitmentHash: String?
}

struct SavePrivateReviewDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var placeId: UUID
    var rating: Double?
    var tags: [String]
    var note: String
    var visitDate: Date
    var visibility: SaveReviewVisibility
    var proofRefs: [SaveReceiptProofRef]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        placeId: UUID,
        rating: Double? = nil,
        tags: [String] = [],
        note: String = "",
        visitDate: Date = Date(),
        visibility: SaveReviewVisibility = .privateOnly,
        proofRefs: [SaveReceiptProofRef] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.placeId = placeId
        self.rating = rating
        self.tags = tags
        self.note = note
        self.visitDate = visitDate
        self.visibility = visibility
        self.proofRefs = proofRefs
        self.createdAt = createdAt
    }
}

struct SaveSearchResult: Identifiable, Hashable {
    var id: String
    var objectType: SaveSearchObjectType
    var userState: SaveSearchUserState
    var title: String
    var subtitle: String
    var statusLabel: String
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var category: PlaceCategory?
    var cityOrArea: String?
    var latitude: Double?
    var longitude: Double?
    var rating: Double?
    var reviewCount: Int?
    var confidence: Double?
    var missingInfo: [String]
    var evidence: [String]
    var recoveryQueries: [String]
    var createdAt: Date
    var canRunRecovery: Bool
    var isRecommendationShell: Bool
    var primaryAction: SaveSearchPrimaryAction
    var distanceMeters: Double? = nil
    var photoURL: String? = nil
    var businessPhotoURLs: [String]? = nil
    var placeHighlights: [String] = []
    var recommendedItems: [RecommendedItem] = []
    var vibeTags: [String] = []
    var accessNotes: [String] = []
    var sourceHandle: String? = nil

    var searchText: String {
        [
            title,
            subtitle,
            statusLabel,
            sourceURL,
            sourcePlatform?.displayName,
            category?.displayName,
            cityOrArea,
            rating.map { "rating \($0)" },
            reviewCount.map { "reviews \($0)" },
            missingInfo.joined(separator: " "),
            evidence.joined(separator: " "),
            recoveryQueries.joined(separator: " "),
            placeHighlights.joined(separator: " "),
            recommendedItems.map(\.displayText).joined(separator: " "),
            vibeTags.joined(separator: " "),
            accessNotes.joined(separator: " "),
            sourceHandle,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    var agentDrawer: SaveAgentActionDrawerModel {
        SaveAgentActionDrawerModel(result: self)
    }

    var evidenceDrawer: SaveEvidenceDrawerModel {
        SaveEvidenceDrawerModel(result: self)
    }
}

extension SaveSearchResult {
    var businessPhotoURLStrings: [String] {
        var values = businessPhotoURLs ?? []
        if let photoURL {
            values.insert(photoURL, at: 0)
        }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingDuplicates()
    }

    var distanceLabel: String? {
        distanceMeters.map(Self.distanceLabel)
    }

    var shareSubject: String {
        "SAV-E Place: \(title)"
    }

    var saveShareURL: URL? {
        SharedPlaceData.from(result: self)?.toURL()
    }

    var shareText: String {
        var lines = [
            "SAV-E Place",
            title,
            subtitle,
            "Type: \(objectType.displayName)",
            "State: \(userState.displayName)"
        ]

        if let category {
            lines.append("Category: \(category.displayName)")
        }
        if let rating {
            lines.append("Rating: \(String(format: "%.1f", rating))")
        }
        if let reviewCount {
            lines.append("Reviews: \(reviewCount)")
        }
        if let sourceURL, !sourceURL.isEmpty {
            lines.append("Source: \(sourceURL)")
        }
        if let saveShareURL {
            lines.append("Open in SAV-E: \(saveShareURL.absoluteString)")
        }
        if !missingInfo.isEmpty {
            lines.append("Needs: \(missingInfo.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    var shareMessage: String {
        var parts = [subtitle]
        if let category {
            parts.append(category.displayName)
        }
        if let rating {
            parts.append(String(format: "%.1f stars", rating))
        }
        if let reviewCount {
            parts.append("\(reviewCount) reviews")
        }
        return parts.joined(separator: " · ")
    }

    var shareNote: String? {
        var parts: [String] = []
        if let rating {
            parts.append(String(format: "%.1f stars", rating))
        }
        if let reviewCount {
            parts.append("\(reviewCount) reviews")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func distanceLabel(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km away", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m away"
    }
}

struct SaveSearchSection: Identifiable, Hashable {
    var id: String
    var label: String?
    var title: String
    var subtitle: String
    var results: [SaveSearchResult]
    var emptyMessage: String?
    var showsNearbySearchAction: Bool

    init(
        id: String,
        label: String? = nil,
        title: String,
        subtitle: String,
        results: [SaveSearchResult],
        emptyMessage: String? = nil,
        showsNearbySearchAction: Bool = false
    ) {
        self.id = id
        self.label = label
        self.title = title
        self.subtitle = subtitle
        self.results = results
        self.emptyMessage = emptyMessage
        self.showsNearbySearchAction = showsNearbySearchAction
    }
}

struct SaveAgentGrounding: Equatable {
    var allowedResultIDs: [String]
    var sectionIDs: [String]
    var hasContext: Bool

    init(sections: [SaveSearchSection]) {
        allowedResultIDs = sections.flatMap { section in
            section.results.map(\.id)
        }
        sectionIDs = sections
            .filter { section in
                !section.results.isEmpty ||
                    section.emptyMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
                    section.showsNearbySearchAction
            }
            .map(\.id)
        hasContext = !allowedResultIDs.isEmpty || !sectionIDs.isEmpty
    }
}

struct SaveAgentAnswer: Equatable {
    enum Source: String, Equatable {
        case deterministic
        case groundedLLM
    }

    var message: String
    var source: Source
    var grounding: SaveAgentGrounding

    init(message: String, source: Source, grounding: SaveAgentGrounding) {
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.grounding = grounding
    }
}

struct SaveSearchResponse: Equatable {
    var query: String
    var assistantMessage: String?
    var agentAnswer: SaveAgentAnswer?
    var fromYourSave: SaveSearchSection
    var additionalSections: [SaveSearchSection]
    var newRecommendations: SaveSearchSection

    init(
        query: String,
        assistantMessage: String? = nil,
        agentAnswer: SaveAgentAnswer? = nil,
        fromYourSave: SaveSearchSection,
        additionalSections: [SaveSearchSection] = [],
        newRecommendations: SaveSearchSection
    ) {
        self.query = query
        self.assistantMessage = assistantMessage
        self.agentAnswer = agentAnswer
        self.fromYourSave = fromYourSave
        self.additionalSections = additionalSections
        self.newRecommendations = newRecommendations
    }
}

extension SaveSearchResponse {
    var resolvedAgentAnswer: SaveAgentAnswer? {
        if let agentAnswer {
            return agentAnswer
        }
        guard let assistantMessage,
              !assistantMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return SaveAgentAnswer(
            message: assistantMessage,
            source: .deterministic,
            grounding: groundedAnswerGrounding
        )
    }

    mutating func replaceAgentAnswer(_ message: String, source: SaveAgentAnswer.Source) {
        assistantMessage = message
        agentAnswer = SaveAgentAnswer(
            message: message,
            source: source,
            grounding: groundedAnswerGrounding
        )
    }

    var groundedAnswerGrounding: SaveAgentGrounding {
        SaveAgentGrounding(sections: groundedAnswerSections)
    }

    var shouldAutoSearchNearbyUnsavedCandidates: Bool {
        fromYourSave.results.isEmpty &&
            newRecommendations.showsNearbySearchAction &&
            newRecommendations.results.isEmpty
    }

    var groundedAnswerSections: [SaveSearchSection] {
        let savedAndReviewSections = saveUsedEvidenceSections
        if isNearbyRecommendationResponse {
            guard fromYourSave.results.isEmpty else { return savedAndReviewSections }
            return savedAndReviewSections + [newRecommendations]
        }
        return savedAndReviewSections + farSavedSections + [newRecommendations]
    }

    var saveUsedEvidenceSections: [SaveSearchSection] {
        ([fromYourSave] + reviewCandidateSections)
            .filter { !$0.results.isEmpty || $0.emptyMessage != nil || $0.showsNearbySearchAction }
    }

    var farSavedSections: [SaveSearchSection] {
        additionalSections.filter { $0.id == "saved-but-not-nearby" }
    }

    var publicDiscoverySections: [SaveSearchSection] {
        [newRecommendations].filter { !$0.results.isEmpty || $0.emptyMessage != nil || $0.showsNearbySearchAction }
    }

    var secondaryDisplaySections: [SaveSearchSection] {
        if isNearbyRecommendationResponse, fromYourSave.results.isEmpty {
            return publicDiscoverySections + farSavedSections
        }
        return farSavedSections + publicDiscoverySections
    }

    private var isNearbyRecommendationResponse: Bool {
        fromYourSave.id == "from-your-save-nearby"
    }

    private var reviewCandidateSections: [SaveSearchSection] {
        additionalSections.filter { $0.id == "review-candidates" }
    }
}

struct FoodPlaceInsight: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var recommendedItems: [RecommendedItem]
    var highlights: [String]
    var vibeTags: [String]
    var accessNotes: [String]
    var sourceHandle: String?
    var sourceURL: String?
    var evidence: [String]
    var isFromSavedPrivateMemory: Bool

    var hasOrderableItems: Bool { !recommendedItems.isEmpty }

    var headline: String {
        if let first = recommendedItems.first { return "Try \(first.displayText)" }
        if let first = highlights.first { return first }
        return "Saved food memory"
    }
}

struct FoodPlaceInsightService {
    func insight(for place: Place) -> FoodPlaceInsight? {
        guard isFoodLike(
            category: place.category,
            text: [place.name, place.address, place.note ?? "", place.savedRecommendedItems.map(\.displayText).joined(separator: " "), place.savedPlaceHighlights.joined(separator: " ")].joined(separator: " ")
        ) else { return nil }
        let recommendedItems = place.savedRecommendedItems
        let highlights = place.savedPlaceHighlights
        let vibeTags = place.savedVibeTags
        let accessNotes = place.savedAccessNotes
        guard !recommendedItems.isEmpty || !highlights.isEmpty || !vibeTags.isEmpty || !accessNotes.isEmpty else { return nil }
        return FoodPlaceInsight(
            id: "place-\(place.id.uuidString)",
            title: place.name,
            subtitle: place.address,
            recommendedItems: recommendedItems,
            highlights: highlights,
            vibeTags: vibeTags,
            accessNotes: accessNotes,
            sourceHandle: place.savedSourceHandle,
            sourceURL: place.sourceUrl,
            evidence: foodEvidence(sourceURL: place.sourceUrl, sourceHandle: place.savedSourceHandle, recommendedItems: recommendedItems, highlights: highlights, vibeTags: vibeTags, accessNotes: accessNotes, fallbackNote: place.note),
            isFromSavedPrivateMemory: true
        )
    }

    func insight(for record: SaveMemoryRecord) -> FoodPlaceInsight? {
        guard record.state == .confirmedPlace || record.state == .reviewCandidate else { return nil }
        let category = record.category ?? .inferred(from: [record.title, record.placeName ?? "", record.address ?? "", record.evidence.joined(separator: " ")].joined(separator: " "))
        guard isFoodLike(category: category, text: record.evidence.joined(separator: " ")) else { return nil }
        guard !record.recommendedItems.isEmpty || !record.placeHighlights.isEmpty || !record.vibeTags.isEmpty || !record.accessNotes.isEmpty else { return nil }
        return FoodPlaceInsight(
            id: "record-\(record.id.uuidString)",
            title: record.displayTitle,
            subtitle: record.address ?? "",
            recommendedItems: record.recommendedItems,
            highlights: record.placeHighlights,
            vibeTags: record.vibeTags,
            accessNotes: record.accessNotes,
            sourceHandle: record.sourceHandle,
            sourceURL: record.sourceURL,
            evidence: record.evidence,
            isFromSavedPrivateMemory: true
        )
    }

    func insight(for result: SaveSearchResult) -> FoodPlaceInsight? {
        guard result.objectType == .savedPlace || result.objectType == .triedMemory || result.objectType == .pendingCandidate || result.objectType == .sourceOnlyClue else { return nil }
        let category = result.category ?? .inferred(from: [result.title, result.subtitle, result.evidence.joined(separator: " ")].joined(separator: " "))
        guard isFoodLike(category: category, text: result.searchText) else { return nil }
        guard !result.recommendedItems.isEmpty || !result.placeHighlights.isEmpty || !result.vibeTags.isEmpty || !result.accessNotes.isEmpty else { return nil }
        return FoodPlaceInsight(
            id: result.id,
            title: result.title,
            subtitle: result.subtitle,
            recommendedItems: result.recommendedItems,
            highlights: result.placeHighlights,
            vibeTags: result.vibeTags,
            accessNotes: result.accessNotes,
            sourceHandle: result.sourceHandle,
            sourceURL: result.sourceURL,
            evidence: result.evidence,
            isFromSavedPrivateMemory: result.userState != .unsaved
        )
    }

    private func isFoodLike(category: PlaceCategory, text: String) -> Bool {
        if category == .food || category == .cafe || category == .bar { return true }
        let lowered = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current).lowercased()
        return lowered.range(of: #"\b(order|dish|menu|ramen|sushi|coffee|cafe|bakery|dessert|brunch|lunch|dinner|restaurant|bar|cocktail|noodle|rice|taco|pizza)\b|推薦|必點|餐|咖啡|甜點|拉麵|拉面|火鍋|火锅|壽司|寿司|牛舌|燒肉|烧肉"#, options: .regularExpression) != nil
    }

    private func foodEvidence(
        sourceURL: String?,
        sourceHandle: String?,
        recommendedItems: [RecommendedItem],
        highlights: [String],
        vibeTags: [String],
        accessNotes: [String],
        fallbackNote: String?
    ) -> [String] {
        var evidence: [String] = []
        if let sourceURL, !sourceURL.isEmpty { evidence.append("Source URL: \(sourceURL)") }
        if let sourceHandle, !sourceHandle.isEmpty { evidence.append("Source handle: @\(sourceHandle)") }
        evidence.append(contentsOf: recommendedItems.map { "Recommended item: \($0.displayText)" })
        evidence.append(contentsOf: highlights.map { "Highlight: \($0)" })
        evidence.append(contentsOf: vibeTags.map { "Vibe: \($0)" })
        evidence.append(contentsOf: accessNotes.map { "Access: \($0)" })
        if let fallbackNote, !fallbackNote.isEmpty { evidence.append(fallbackNote) }
        return evidence.removingDuplicatesForFoodInsight()
    }
}

private extension Array where Element == String {
    func removingDuplicatesForFoodInsight() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

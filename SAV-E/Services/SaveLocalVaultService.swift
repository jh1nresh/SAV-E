import Foundation

enum SaveLocalVaultError: LocalizedError {
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "SAV-E local memory storage is unavailable."
        }
    }
}

final class SaveLocalVaultService {
    static let shared = SaveLocalVaultService()

    private let fileManager: FileManager
    private let fileName = "save-memory-records.json"
    private let overrideVaultURL: URL?

    init(fileManager: FileManager = .default, overrideVaultURL: URL? = nil) {
        self.fileManager = fileManager
        self.overrideVaultURL = overrideVaultURL
    }

    func append(_ record: SaveMemoryRecord) throws {
        var records = try loadRecords()
        records.insert(record, at: 0)
        try save(records)
    }

    func recentRecords(limit: Int = 25) throws -> [SaveMemoryRecord] {
        Array(try loadRecords().prefix(limit))
    }

    func confirmedPlaces(limit: Int = 250) throws -> [Place] {
        Array(
            try loadRecords()
                .compactMap(\.confirmedPlace)
                .prefix(limit)
        )
    }

    func saveSourceOnly(url: URL, note: String? = nil) throws -> SaveMemoryRecord {
        let diagnostic = sourceOnlyDiagnostic(url: url, note: note)
        let record = SaveMemoryRecord(
            state: .sourceOnly,
            sourceURL: url.absoluteString,
            sourceText: note,
            title: sourceOnlyDisplayName(for: url),
            evidence: diagnostic.found + diagnostic.attempts + diagnosticSearchEvidence(diagnostic),
            evidenceDiagnostic: diagnostic
        )
        try append(record)
        return record
    }

    func saveReviewCandidate(_ candidate: PendingReviewCandidate) throws -> SaveMemoryRecord {
        let record = SaveMemoryRecord(
            state: candidate.isSourceOnly ? .sourceOnly : .reviewCandidate,
            sourceURL: candidate.sourceURL,
            sourceText: candidate.sourceText,
            title: candidate.candidateName,
            placeName: candidate.isSourceOnly ? nil : candidate.candidateName,
            address: candidate.address.isEmpty ? nil : candidate.address,
            evidence: candidate.evidence,
            evidenceDiagnostic: candidate.evidenceDiagnostic,
            placeHighlights: candidate.placeHighlights,
            recommendedItems: candidate.recommendedItems,
            vibeTags: candidate.vibeTags,
            accessNotes: candidate.accessNotes,
            sourceHandle: candidate.sourceHandle,
            createdAt: candidate.savedAt
        )
        try append(record)
        return record
    }

    func saveReviewCandidate(_ candidate: PlaceReviewCandidate) throws -> SaveMemoryRecord {
        let record = SaveMemoryRecord(
            state: .reviewCandidate,
            title: candidate.name,
            placeName: candidate.name,
            address: candidate.address.isEmpty ? nil : candidate.address,
            evidence: candidate.evidence,
            placeHighlights: candidate.placeHighlights,
            recommendedItems: candidate.recommendedItems,
            vibeTags: candidate.vibeTags,
            accessNotes: candidate.accessNotes,
            sourceHandle: candidate.sourceHandle,
            createdAt: candidate.createdAt
        )
        try append(record)
        return record
    }

    func saveConfirmedPlace(_ place: Place) throws -> SaveMemoryRecord {
        let record = SaveMemoryRecord(
            state: .confirmedPlace,
            sourceURL: place.sourceUrl,
            sourceText: place.note,
            title: place.name,
            placeName: place.name,
            address: place.address,
            evidence: confirmedPlaceEvidence(place),
            placeHighlights: place.savedPlaceHighlights,
            recommendedItems: place.savedRecommendedItems,
            vibeTags: place.savedVibeTags,
            accessNotes: place.savedAccessNotes,
            sourceHandle: place.savedSourceHandle,
            latitude: place.latitude,
            longitude: place.longitude,
            category: place.category,
            status: place.status,
            rating: place.rating ?? place.googleRating,
            createdAt: place.createdAt,
            googlePlaceId: place.googlePlaceId,
            sourceImageUrl: place.sourceImageUrl,
            businessPhotoUrls: place.businessPhotoUrls
        )
        var records = try loadRecords()
        records.removeAll { existingRecord in
            guard existingRecord.state == .confirmedPlace,
                  let existingPlace = existingRecord.confirmedPlace else {
                return false
            }
            return existingPlace.id == place.id || existingPlace.matches(place)
        }
        records.insert(record, at: 0)
        try save(records)
        return record
    }

    private func confirmedPlaceEvidence(_ place: Place) -> [String] {
        var evidence: [String] = []
        if let sourceUrl = place.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceUrl.isEmpty {
            evidence.append("Source URL: \(sourceUrl)")
        }
        if let sourceHandle = place.savedSourceHandle?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceHandle.isEmpty {
            evidence.append("Source handle: @\(sourceHandle)")
        }
        evidence.append(contentsOf: place.savedPlaceHighlights.map { "Highlight: \($0)" })
        evidence.append(contentsOf: place.savedRecommendedItems.map { "Highlight: Recommended item: \($0.displayText)" })
        evidence.append(contentsOf: place.savedVibeTags.map { "Vibe: \($0)" })
        evidence.append(contentsOf: place.savedAccessNotes.map { "Access: \($0)" })
        if let note = place.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            evidence.append(note)
        }
        var seen = Set<String>()
        return evidence.filter { seen.insert($0).inserted }
    }

    private func loadRecords() throws -> [SaveMemoryRecord] {
        guard let url = vaultURL() else { throw SaveLocalVaultError.storageUnavailable }
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.saveVault.decode([SaveMemoryRecord].self, from: data)
    }

    private func save(_ records: [SaveMemoryRecord]) throws {
        guard let url = vaultURL() else { throw SaveLocalVaultError.storageUnavailable }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.saveVault.encode(records)
        try data.write(to: url, options: [.atomic])
    }

    private func vaultURL() -> URL? {
        if let overrideVaultURL { return overrideVaultURL }
        if let appGroupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: SAVEProductionConfig.appGroupSuiteName) {
            return appGroupURL.appendingPathComponent(fileName)
        }
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }

    private func sourceOnlyDisplayName(for url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("/reel/") || path.contains("/reels/") { return "Instagram reel" }
        if url.host()?.lowercased().contains("instagram") == true { return "Instagram link" }
        if url.host()?.lowercased().matchesDomain("xiaohongshu.com") == true || url.host()?.lowercased().matchesDomain("xhslink.com") == true { return "Xiaohongshu link" }
        if url.host()?.lowercased().matchesDomain("douyin.com") == true || url.host()?.lowercased().matchesDomain("iesdouyin.com") == true { return "Douyin link" }
        return url.host() ?? url.absoluteString
    }

    private func sourceOnlyDiagnostic(url: URL, note: String?) -> SocialPlaceEvidenceDiagnostic {
        var found = ["Source URL: \(url.absoluteString)"]
        if note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            found.append("Shared text/caption was present but did not contain a verified place candidate")
        }
        let searchQueries = sourceRecoverySearchQueries(url: url, note: note)
        return SocialPlaceEvidenceDiagnostic(
            found: found,
            attempts: [
                "Saved the original source before place evidence was verified",
                "Kept this as a source-only clue instead of inventing a place",
                "Prepared public web search fallback queries for source-only recovery"
            ],
            missingFields: [
                "Verified place name",
                "Verified address",
                "Verified coordinates"
            ],
            nextBestClue: "Run the suggested public searches, or share a caption, screenshot/OCR frame, map link, or visible venue handle.",
            suggestedSearchQueries: searchQueries.isEmpty ? nil : searchQueries,
            recoveryPlan: SocialPlaceEvidenceRecoveryPlan(
                sourceURL: url.absoluteString,
                evidenceAtoms: sourceOnlyEvidenceAtoms(url: url, note: note),
                queriesToTry: searchQueries,
                blockedResultHints: [
                    "creator profile without venue name/address",
                    "generic social shell or login wall",
                    "aggregator/list page without address or map coordinates",
                    "map home/directions page without canonical place identity"
                ],
                requiredEvidence: [
                    "Verified place name",
                    "Verified address",
                    "Verified coordinates"
                ],
                decision: .sourceOnly,
                allowsDirectSave: false
            ),
            rejectedEvidence: [
                SocialPlaceRejectedEvidence(value: "source-only link", reason: "kept as receipt until place evidence is verified")
            ]
        )
    }

    private func diagnosticSearchEvidence(_ diagnostic: SocialPlaceEvidenceDiagnostic) -> [String] {
        (diagnostic.suggestedSearchQueries ?? []).map { "Suggested public search: \($0)" }
    }

    private func sourceOnlyEvidenceAtoms(url: URL, note: String?) -> [String] {
        var atoms = [
            "source_url: \(url.absoluteString)",
            "source_host: \(url.host() ?? "unknown")"
        ]
        if note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            atoms.append("shared_note: present")
        } else {
            atoms.append("shared_note: none")
        }
        return atoms
    }

    private func sourceRecoverySearchQueries(url: URL, note: String?) -> [String] {
        var queries: [String] = []
        let host = url.host()?.lowercased() ?? ""
        if let reelID = instagramReelID(in: url) {
            queries.append("instagram reel \(reelID) place")
            queries.append("\(reelID) restaurant venue")
        } else if !host.isEmpty {
            queries.append("\(host) \(url.lastPathComponent) place")
        }

        let cleanedNote = (note ?? "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedNote.isEmpty {
            queries.append("\"\(String(cleanedNote.prefix(80)))\" place")
        }

        if let canonicalURL = canonicalSearchURL(from: url) {
            queries.append("\"\(canonicalURL)\"")
        }

        return Array(appendUnique([], queries).prefix(4))
    }

    private func instagramReelID(in url: URL) -> String? {
        guard url.host()?.lowercased().contains("instagram") == true else { return nil }
        let components = url.pathComponents
        guard let markerIndex = components.firstIndex(where: { $0.lowercased() == "reel" || $0.lowercased() == "reels" }),
              components.indices.contains(markerIndex + 1) else { return nil }
        let id = components[markerIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return id.isEmpty ? nil : id
    }

    private func canonicalSearchURL(from url: URL) -> String? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let value = components?.url?.absoluteString ?? url.absoluteString
        return value.isEmpty ? nil : value
    }

    private func appendUnique(_ values: [String], _ newValues: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values + newValues {
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

private extension SaveMemoryRecord {
    var confirmedPlace: Place? {
        guard state == .confirmedPlace else { return nil }
        guard let latitude, let longitude, latitude != 0 || longitude != 0 else { return nil }

        let name = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let address = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Place(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: googlePlaceId,
            category: category ?? PlaceCategory.inferred(from: "\(name) \(address)"),
            status: status ?? .wantToGo,
            rating: rating,
            note: sourceText,
            sourceUrl: sourceURL,
            sourcePlatform: SourcePlatform.from(urlString: sourceURL),
            sourceImageUrl: sourceImageUrl,
            businessPhotoUrls: businessPhotoUrls,
            extractedDishes: recommendedItems.map(\.name).nilIfEmpty,
            priceRange: nil,
            recommender: sourceHandle,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: createdAt,
            visibility: .privateMemory,
            socialSignal: nil,
            placeHighlights: placeHighlights.nilIfEmpty,
            recommendedItems: recommendedItems.nilIfEmpty,
            vibeTags: vibeTags.nilIfEmpty,
            accessNotes: accessNotes.nilIfEmpty,
            sourceHandle: sourceHandle
        )
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

private extension JSONEncoder {
    static var saveVault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var saveVault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    func matchesDomain(_ domain: String) -> Bool {
        self == domain || hasSuffix(".\(domain)")
    }
}

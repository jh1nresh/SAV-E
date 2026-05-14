import CoreLocation
import Foundation

struct GoogleTakeoutImportResult {
    var fileName: String
    var parsedAt: Date
    var drafts: [ImportedPlaceDraft]

    var readyDrafts: [ImportedPlaceDraft] {
        drafts.filter { $0.reviewState == .readyToSave }
    }

    var reviewDrafts: [ImportedPlaceDraft] {
        drafts.filter {
            if case .needsReview = $0.reviewState {
                return true
            }
            return false
        }
    }
}

struct GoogleTakeoutSaveSummary {
    var saved: Int
    var skippedDuplicates: Int
    var reviewDrafts: Int
}

struct ImportedPlaceDraft: Identifiable, Hashable {
    enum ReviewState: Hashable {
        case readyToSave
        case needsReview(String)
    }

    let id: UUID
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var sourceURL: String?
    var sourceFile: String
    var sourceFormat: String
    var rawSnippet: String?
    var reviewState: ReviewState

    init(
        id: UUID = UUID(),
        name: String,
        address: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        sourceURL: String? = nil,
        sourceFile: String,
        sourceFormat: String,
        rawSnippet: String? = nil,
        reviewState: ReviewState
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.sourceURL = sourceURL
        self.sourceFile = sourceFile
        self.sourceFormat = sourceFormat
        self.rawSnippet = rawSnippet
        self.reviewState = reviewState
    }

    var hasReliableCoordinate: Bool {
        guard let latitude, let longitude else { return false }
        return CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            && abs(latitude) > 0.000001
            && abs(longitude) > 0.000001
    }

    var deduplicationKey: String {
        if let normalized = sourceURL?.normalizedImportURLString() {
            return normalized
        }

        let normalizedName = name.normalizedImportToken
        let normalizedAddress = address.normalizedImportToken
        if !normalizedAddress.isEmpty {
            return "\(normalizedName)|\(normalizedAddress)"
        }
        return normalizedName
    }

    func toPlace() -> Place? {
        guard hasReliableCoordinate,
              let latitude,
              let longitude else {
            return nil
        }

        return Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: .food,
            status: .wantToGo,
            rating: nil,
            note: rawSnippet,
            sourceUrl: sourceURL,
            sourcePlatform: .googleMaps,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }
}

extension Place {
    var importDeduplicationKey: String {
        if let normalized = sourceUrl?.normalizedImportURLString() {
            return normalized
        }

        let normalizedName = name.normalizedImportToken
        let normalizedAddress = address.normalizedImportToken
        if !normalizedAddress.isEmpty {
            return "\(normalizedName)|\(normalizedAddress)"
        }
        return normalizedName
    }
}

private extension String {
    var normalizedImportToken: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func normalizedImportURLString() -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.queryItems = components.queryItems?
            .filter { !$0.name.lowercased().hasPrefix("utm_") }
            .sorted { lhs, rhs in lhs.name.lowercased() < rhs.name.lowercased() }
        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }
        return components.string
    }
}

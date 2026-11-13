import Foundation
import SwiftUI

/// Original account-owned records, without inventing coordinates, save dates,
/// or a single note/status to stand in for several private visit records.
struct SavvyPlaceHistorySnapshot: Equatable {
    let ownerSubject: String
    let savedPlaces: [SaveInkSavedPlaceRecord]
    let visits: [SaveInkVisitRecord]

    var isEmpty: Bool { savedPlaces.isEmpty && visits.isEmpty }
}

@MainActor
enum SavvyPlaceHistory {
    enum Failure: Error, Equatable {
        case missingOwner
        case unreadablePlaces
        case unreadableVisits
    }

    /// Reads only. A present shared key is authoritative, including when it is
    /// empty or corrupt. Ownerless records and unscoped visit keys are excluded.
    static func load(
        ownerSubject: String,
        placesDefaults: UserDefaults = SavePlaceLinkGate.sharedPlacesDefaults(),
        legacyDefaults: UserDefaults = .standard,
        visitsDefaults: UserDefaults = .standard
    ) throws -> SavvyPlaceHistorySnapshot {
        guard !ownerSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingOwner
        }
        let key = SavePlaceLinkGate.placesKey
        let placesStore = placesDefaults.object(forKey: key) == nil ? legacyDefaults : placesDefaults
        let records: [SaveInkSavedPlaceRecord] = try decode(
            [SaveInkSavedPlaceRecord].self, key: key, defaults: placesStore,
            failure: .unreadablePlaces
        ) ?? []
        let visits: [SaveInkVisitRecord] = try decode(
            [SaveInkVisitRecord].self, key: "save.ink.visits.v1.\(ownerSubject)",
            defaults: visitsDefaults, failure: .unreadableVisits
        ) ?? []
        return SavvyPlaceHistorySnapshot(
            ownerSubject: ownerSubject,
            savedPlaces: SaveInkNotebookStore.visibleSavedRecords(records, owner: ownerSubject, scoped: true),
            visits: visits
        )
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type, key: String, defaults: UserDefaults, failure: Failure
    ) throws -> Value? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else { throw failure }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw failure }
    }
}

/// A read-only archive inside the main app. The presenting verified account
/// root owns session invalidation and dismisses this sheet on account changes.
struct SavvyPlaceHistorySheet: View {
    let ownerSubject: String
    var places: [Place] = []
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: SavvyPlaceHistorySnapshot?
    @State private var failure: SavvyPlaceHistory.Failure?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(localized("Your earlier saved places and visits stay here. Places without a known location stay off the map. These records are shown only to you.",
                                   "過往保存的地點與到訪紀錄都留在這裡。沒有確定位置的地點不會放上地圖；這裡的紀錄只向你顯示。"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let failure {
                        failureContent(failure)
                    } else if let snapshot, snapshot.ownerSubject == ownerSubject {
                        if snapshot.isEmpty {
                            Text(localized("No earlier records for this account.", "這個帳號沒有過往紀錄。"))
                                .foregroundStyle(.secondary)
                        } else {
                            if !snapshot.savedPlaces.isEmpty {
                                Text(localized("Earlier saved places", "過往保存的地點")).font(.headline)
                                ForEach(Array(snapshot.savedPlaces.enumerated()), id: \.offset) { _, place in
                                    savedPlaceCard(place)
                                }
                            }
                            if !snapshot.visits.isEmpty {
                                Text(localized("Visit history", "到訪紀錄")).font(.headline)
                                ForEach(snapshot.visits.sorted { $0.visitedAt > $1.visitedAt }) { visit in
                                    visitCard(visit, snapshot: snapshot)
                                }
                            }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(localized("Place history", "地點紀錄"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Done", "完成")) { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .task(id: ownerSubject) { reload() }
    }

    private func savedPlaceCard(_ place: SaveInkSavedPlaceRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(place.name).font(.headline)
            Text(localized("Saved · location not recorded", "已保存・沒有位置紀錄"))
                .font(.caption).foregroundStyle(.secondary)
            if !place.street.isEmpty { Text(place.street).font(.subheadline) }
            if !place.blurb.isEmpty { Text(place.blurb).font(.subheadline) }
            if !place.detailNote.isEmpty { Text(place.detailNote).textSelection(.enabled) }
            if !place.sourceLabel.isEmpty {
                Text(place.sourceLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
        .historyCard()
    }

    private func visitCard(_ visit: SaveInkVisitRecord, snapshot: SavvyPlaceHistorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(placeName(for: visit, snapshot: snapshot)).font(.headline)
            Text(visit.visitedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.subheadline).foregroundStyle(.secondary)
            Text(visit.verification == .verified
                 ? localized("Location-verified visit", "位置已驗證的到訪")
                 : localized("Unverified visit", "未驗證的到訪"))
                .font(.subheadline)
            Text(visit.visibility == .private
                 ? localized("Original audience: Private", "原本的可見範圍：私人")
                 : localized("Original audience: Public", "原本的可見範圍：公開"))
                .font(.caption).foregroundStyle(.secondary)
            if !visit.comment.isEmpty { Text(visit.comment).textSelection(.enabled) }
            if let sentiment = visit.sentiment {
                Text(sentiment.title(language: language.language)).font(.subheadline)
            }
            if let anomaly = visit.anomaly {
                Text(anomalyLabel(anomaly)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .historyCard()
    }

    private func placeName(for visit: SaveInkVisitRecord, snapshot: SavvyPlaceHistorySnapshot) -> String {
        if let saved = snapshot.savedPlaces.first(where: { $0.id == visit.placeID }) { return saved.name }
        if let id = UUID(uuidString: visit.placeID),
           let place = places.first(where: { $0.savedIDs.contains(id) }) { return place.name }
        return localized("Earlier place · name unavailable", "過往地點・名稱暫時無法取得")
    }

    private func anomalyLabel(_ anomaly: SaveInkAnomaly) -> String {
        switch anomaly {
        case .simulatedLocation: localized("Recorded flag: simulated location", "原紀錄註記：模擬位置")
        case .implausibleSpeed: localized("Recorded flag: implausible travel speed", "原紀錄註記：移動速度異常")
        case .dailyCap: localized("Recorded flag: daily verification limit", "原紀錄註記：當日驗證次數上限")
        }
    }

    private func failureContent(_ failure: SavvyPlaceHistory.Failure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(failure == .missingOwner
                 ? localized("Sign in to view this account’s earlier records.", "請登入後查看這個帳號的過往紀錄。")
                 : localized("Earlier records could not be read. Nothing has been changed.", "無法讀取過往紀錄，原本的資料沒有變更。"))
            Button(localized("Retry", "重試"), action: reload)
                .frame(minWidth: 44, minHeight: 44)
        }
        .historyCard()
    }

    private func reload() {
        snapshot = nil
        failure = nil
        do { snapshot = try SavvyPlaceHistory.load(ownerSubject: ownerSubject) }
        catch let error as SavvyPlaceHistory.Failure { failure = error }
        catch { failure = .unreadablePlaces }
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

private extension View {
    func historyCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

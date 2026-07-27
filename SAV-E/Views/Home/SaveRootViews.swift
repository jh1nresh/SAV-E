import SwiftUI

struct SaveHomeView: View {
    @ObservedObject var store: TripPackStore
    @ObservedObject var mapViewModel: MapViewModel
    let onOpenDrawer: (DrawerLaunchTarget, UUID?) -> Void
    let onOpenSavedPlace: (Place) -> Void
    let onOpenSaves: () -> Void
    let onOpenTrips: () -> Void
    let onOpenTrip: (UUID) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                captureCard
                nextActions
                tripSection
                recentSavesSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(SaveDottedBackground().ignoresSafeArea())
        .navigationTitle(localized("Home", "首頁"))
        .accessibilityIdentifier("home.root")
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                localized("Turn a clue into a place you can use", "把線索變成真正能使用的地點"),
                systemImage: "link.badge.plus"
            )
            .font(.title3.bold())
            .foregroundStyle(Color.saveInk)

            Text(localized(
                "Paste or share a social post, map link, or message. SAV-E investigates it before anything reaches your map or trip.",
                "貼上或分享社群貼文、地圖連結或訊息。SAV-E 會先分析，確認後才會進入地圖或行程。"
            ))
            .font(.subheadline)
            .foregroundStyle(Color.saveMutedText)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                onOpenDrawer(.addLink, nil)
            } label: {
                Label(
                    localized("Paste or share link", "貼上／分享連結"),
                    systemImage: "plus"
                )
                .font(.headline)
                .foregroundStyle(Color.saveInk)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Color.saveCoral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.capture")
        }
        .padding(18)
        .saveNotebookPage(cornerRadius: 22)
    }

    private var nextActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Next", "下一步"))
                .font(.title2.bold())
                .foregroundStyle(Color.saveInk)

            HStack(spacing: 12) {
                SaveHomeMetricButton(
                    title: localized("Review", "待確認"),
                    value: "\(mapViewModel.reviewCandidates.count)",
                    systemImage: "checklist.unchecked",
                    tint: .saveCoral,
                    action: { onOpenDrawer(.review, nil) }
                )
                .accessibilityIdentifier("home.review")

                SaveHomeMetricButton(
                    title: localized("Map Stamps", "地圖章"),
                    value: "\(mapViewModel.places.count)",
                    systemImage: "checkmark.seal.fill",
                    tint: .saveMint,
                    action: onOpenSaves
                )
                .accessibilityIdentifier("home.saves")
            }
        }
    }

    @ViewBuilder
    private var tripSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Continue", "繼續"))
                .font(.title2.bold())
                .foregroundStyle(Color.saveInk)

            if let trip = store.suggestedTrip {
                Button {
                    store.selectTrip(trip.id)
                    onOpenTrip(trip.id)
                } label: {
                    SaveHomeTripCard(trip: trip)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.trip.\(trip.id.uuidString)")
            } else {
                Button(action: onOpenTrips) {
                    HStack(spacing: 14) {
                        SaveIconTile(
                            systemName: "suitcase.rolling.fill",
                            size: 48,
                            fill: Color.saveHoney.opacity(0.38),
                            foreground: .saveCoralInk
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("Start a Trip Pack", "建立 Trip Pack"))
                                .font(.headline)
                                .foregroundStyle(Color.saveInk)
                            Text(localized(
                                "Plan only when your confirmed places are ready.",
                                "等已確認地點準備好，再開始規劃。"
                            ))
                            .font(.subheadline)
                            .foregroundStyle(Color.saveMutedText)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .saveNotebookPage(cornerRadius: 20)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.openTrips")
            }
        }
    }

    @ViewBuilder
    private var recentSavesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localized("Recent Map Stamps", "最近地圖章"))
                    .font(.title2.bold())
                    .foregroundStyle(Color.saveInk)
                Spacer()
                if !recentPlaces.isEmpty {
                    Button(localized("See all", "查看全部"), action: onOpenSaves)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.saveCocoa)
                }
            }

            if recentPlaces.isEmpty {
                Text(localized(
                    "Confirmed places will appear here after Review.",
                    "完成確認後，收藏地點會出現在這裡。"
                ))
                .font(.subheadline)
                .foregroundStyle(Color.saveMutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .saveNotebookPage(cornerRadius: 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentPlaces.enumerated()), id: \.element.id) { index, place in
                        SaveRootPlaceRow(place: place) {
                            onOpenSavedPlace(place)
                        }

                        if index < recentPlaces.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .saveNotebookPage(cornerRadius: 20)
            }
        }
        .accessibilityIdentifier("home.recentSaves")
    }

    private var recentPlaces: [Place] {
        Array(mapViewModel.places.sorted { $0.createdAt > $1.createdAt }.prefix(3))
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

struct SaveLibraryView: View {
    let places: [Place]
    let reviewCandidates: [PlaceReviewCandidate]
    let onOpenCapture: () -> Void
    let onOpenReview: () -> Void
    let onOpenSavedPlace: (Place) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                reviewCard
                savedPlacesSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(SaveDottedBackground().ignoresSafeArea())
        .navigationTitle(localized("Saves", "收藏"))
        .toolbar {
            if !places.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    SaveGlobalCaptureToolbarButton(action: onOpenCapture)
                }
            }
        }
        .accessibilityIdentifier("saves.root")
    }

    private var reviewCard: some View {
        Button(action: onOpenReview) {
            HStack(spacing: 14) {
                SaveMemoryBadge(state: .ready, size: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("Waiting for Review", "等待確認"))
                        .font(.headline)
                        .foregroundStyle(Color.saveInk)
                    Text(reviewCandidates.isEmpty
                         ? localized("No clues need your decision.", "目前沒有需要你確認的線索。")
                         : localized(
                            "Clues need your decision before becoming Map Stamps.",
                            "線索需要確認，才會成為地圖章。"
                         ))
                    .font(.subheadline)
                    .foregroundStyle(Color.saveMutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                VStack(spacing: 6) {
                    Text("\(reviewCandidates.count)")
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(Color.saveInk)
                        .frame(minWidth: 40, minHeight: 40)
                        .saveNotebookSurface(
                            cornerRadius: 12,
                            fill: .saveCoral,
                            opacity: 0.72,
                            strokeOpacity: 0.5
                        )

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .saveNotebookPage(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("saves.review")
    }

    @ViewBuilder
    private var savedPlacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localized("Map Stamps", "地圖章"))
                    .font(.title2.bold())
                    .foregroundStyle(Color.saveInk)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(localized("Confirmed", "已確認"))
                    Text("\(places.count)")
                        .monospacedDigit()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.saveInk)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .saveNotebookSurface(
                    cornerRadius: 11,
                    fill: .saveMint,
                    opacity: 0.72,
                    strokeOpacity: 0.5
                )
            }

            if sortedPlaces.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        localized("No confirmed places yet", "還沒有已確認地點"),
                        systemImage: "mappin.slash"
                    )
                    .font(.headline)
                    .foregroundStyle(Color.saveInk)

                    Text(localized(
                        "Add a link first. SAV-E keeps uncertain clues in Review instead of placing guesses on your map.",
                        "先加入連結。SAV-E 會把不確定的線索留在待確認，不會把猜測直接放上地圖。"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.saveMutedText)
                    .fixedSize(horizontal: false, vertical: true)

                    Button(action: onOpenCapture) {
                        Label(localized("Paste or share link", "貼上／分享連結"), systemImage: "link.badge.plus")
                            .font(.headline)
                            .foregroundStyle(Color.saveInk)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .background(Color.saveCoral, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .saveNotebookPage(cornerRadius: 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedPlaces.enumerated()), id: \.element.id) { index, place in
                        SaveRootPlaceRow(place: place) {
                            onOpenSavedPlace(place)
                        }
                        .accessibilityIdentifier("saves.place.\(place.id.uuidString)")

                        if index < sortedPlaces.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .saveNotebookPage(cornerRadius: 20)
            }
        }
    }

    private var sortedPlaces: [Place] {
        places.sorted { $0.createdAt > $1.createdAt }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

struct SaveMapRootView: View {
    @ObservedObject var mapViewModel: MapViewModel
    let shouldFocusOnUserLocation: Bool
    let onOpenCapture: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        MapView(
            viewModel: mapViewModel,
            shouldFocusOnUserLocationOnLaunch: shouldFocusOnUserLocation
        )
        .navigationTitle(languageSettings.localized(english: "Map", traditionalChinese: "地圖"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SaveGlobalCaptureToolbarButton(action: onOpenCapture)
            }
        }
        .accessibilityIdentifier("map.root")
    }
}

struct SaveGlobalCaptureToolbarButton: View {
    let action: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        Button(action: action) {
            Image(systemName: "link.badge.plus")
        }
        .accessibilityLabel(languageSettings.localized(
            english: "Paste or share link",
            traditionalChinese: "貼上／分享連結"
        ))
        .accessibilityIdentifier("root.capture")
    }
}

private struct SaveHomeMetricButton: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SaveIconTile(
                        systemName: systemImage,
                        size: 34,
                        fill: tint,
                        foreground: .saveInk
                    )
                    Spacer()
                    Text(value)
                        .font(.title2.monospacedDigit().bold())
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.saveInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .saveNotebookPage(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}

private struct SaveHomeTripCard: View {
    let trip: Trip
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        HStack(spacing: 14) {
            SaveIconTile(
                systemName: "suitcase.rolling.fill",
                size: 48,
                fill: Color.saveHoney.opacity(0.38),
                foreground: .saveCoralInk
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.headline)
                    .foregroundStyle(Color.saveInk)
                Text([trip.city, trip.dateRangeText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.saveMutedText)
                    .lineLimit(1)
                Text(languageSettings.localized(
                    english: "\(trip.places.count) confirmed stops",
                    traditionalChinese: "\(trip.places.count) 個已確認地點"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.saveCocoa)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .saveNotebookPage(cornerRadius: 20)
    }
}

private struct SaveRootPlaceRow: View {
    let place: Place
    let action: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SaveMemoryBadge(state: .saved(place.category), size: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.saveInk)
                        .lineLimit(1)
                    Text(addressText)
                        .font(.subheadline)
                        .foregroundStyle(Color.saveMutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.name), \(addressText)")
        .accessibilityHint(languageSettings.localized(
            english: "Open Map Stamp details",
            traditionalChinese: "打開地圖章詳情"
        ))
    }

    private var addressText: String {
        let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty
            ? languageSettings.localized(english: "Selected on map", traditionalChinese: "從地圖選取")
            : address
    }
}

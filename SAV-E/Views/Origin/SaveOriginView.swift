import SwiftUI

struct SaveOriginCapture: Identifiable, Hashable {
    let id: UUID
    let sourceURL: String?
    let rawText: String?
    let title: String?
    let createdAt: Date

    var originalURL: URL? {
        guard let sourceURL,
              let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              url.host != nil
        else { return nil }
        return url
    }

    var hasDisplayableSource: Bool {
        rawText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || originalURL != nil
    }
}

struct SaveOriginView: View {
    let places: [Place]
    let onSave: (Place) async throws -> Void
    let onSkip: (Place) async throws -> Void
    let onOpenPassport: () -> Void

    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var dragOffset: CGSize = .zero
    @State private var workingPlaceID: UUID?
    @State private var actionError: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            BrandHeader {
                EmptyView()
            }
            .placed(x: 0, y: 48, width: AtlasMetrics.width, height: 51)

            VStack(alignment: .leading, spacing: 14) {
                heading
                cardDeck
                swipeControls
            }
            .padding(.horizontal, 16)
            .placed(x: 0, y: 105, width: AtlasMetrics.width, height: 674)
        }
        .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
        .environment(\.atlasPresentation, atlasPresentation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("origin.root")
        .alert(
            localized("Couldn’t finish that action", "無法完成這個動作"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button(languageSettings.text(.ok)) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("DISCOVER FROM SAVVY", "探索 SAVVY 推薦"))
                .font(AtlasType.body(11))
                .tracking(1.1)
                .foregroundStyle(SaveAtlasPalette.muted)
            Text(localized("What should we eat?", "下一餐吃什麼？"))
                .font(AtlasType.display(34))
                .foregroundStyle(SaveAtlasPalette.forest)
            Text(localized(
                "Swipe left to save. Swipe right to skip.",
                "左滑收藏，右滑跳過。"
            ))
            .font(AtlasType.body(15))
            .foregroundStyle(SaveAtlasPalette.muted)
        }
    }

    @ViewBuilder
    private var cardDeck: some View {
        if foodPlaces.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(SaveAtlasPalette.coral)
                Text(localized("You’re caught up", "推薦都看完了"))
                    .font(AtlasType.display(22))
                    .foregroundStyle(SaveAtlasPalette.ink)
                Text(localized(
                    "New food posts from people and guides you follow will appear here.",
                    "追蹤的朋友與美食指南有新貼文時，會出現在這裡。"
                ))
                .font(AtlasType.body(13))
                .foregroundStyle(SaveAtlasPalette.muted)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 430, alignment: .center)
            .background(SaveAtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .accessibilityIdentifier("origin.empty")
        } else {
            ZStack {
                ForEach(Array(foodPlaces.prefix(3).reversed())) { place in
                    foodCard(place, isActive: place.id == foodPlaces.first?.id)
                        .scaleEffect(place.id == foodPlaces.first?.id ? 1 : 0.96)
                        .offset(y: place.id == foodPlaces.first?.id ? 0 : 9)
                        .allowsHitTesting(place.id == foodPlaces.first?.id)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 430)
        }
    }

    private func foodCard(_ place: Place, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                foodPhoto(place)

                LinearGradient(
                    colors: [.clear, SaveAtlasPalette.ink.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    if let signal = place.socialSignal {
                        Label(signal.displayText, systemImage: signal.kind.pinSystemImage)
                            .font(AtlasType.display(12))
                            .foregroundStyle(SaveAtlasPalette.paper)
                    }
                    Text(place.name)
                        .font(AtlasType.display(28))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(18)

                swipeDecisionOverlay
            }
            .frame(height: 305)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(
                        place.category.displayName(language: languageSettings.language),
                        systemImage: place.category.iconName
                    )
                    if let rating = place.googleRating ?? place.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                }
                .font(AtlasType.display(12))
                .foregroundStyle(SaveAtlasPalette.forest)

                Text(place.note?.trimmingCharacters(in: .whitespacesAndNewlines).originNonEmpty
                     ?? place.address)
                    .font(AtlasType.body(14))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineLimit(3)

                if let handle = place.savedSourceHandle?.originNonEmpty {
                    Text("@\(handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))")
                        .font(AtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 430, alignment: .top)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.12), radius: 14, y: 8)
        .offset(isActive ? dragOffset : .zero)
        .rotationEffect(.degrees(isActive ? Double(dragOffset.width / 22) : 0))
        .gesture(swipeGesture(for: place), including: isActive ? .all : .none)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("origin.foodCard.\(place.id.uuidString)")
    }

    @ViewBuilder
    private func foodPhoto(_ place: Place) -> some View {
        if let value = place.businessPhotoURLStrings.first,
           let url = URL(string: value) {
            CachedAsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    foodPhotoFallback(place)
                }
            }
        } else {
            foodPhotoFallback(place)
        }
    }

    private func foodPhotoFallback(_ place: Place) -> some View {
        ZStack {
            LinearGradient(
                colors: [SaveAtlasPalette.mint, SaveAtlasPalette.honey.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: place.category.iconName)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(SaveAtlasPalette.forest.opacity(0.72))
        }
    }

    @ViewBuilder
    private var swipeDecisionOverlay: some View {
        if abs(dragOffset.width) > 38 {
            Text(dragOffset.width < 0
                 ? localized("SAVE", "收藏")
                 : localized("SKIP", "跳過"))
                .font(AtlasType.display(22))
                .tracking(1.2)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    dragOffset.width < 0 ? SaveAtlasPalette.coral : SaveAtlasPalette.forest,
                    in: Capsule()
                )
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: dragOffset.width < 0 ? .topTrailing : .topLeading)
        }
    }

    private var swipeControls: some View {
        HStack(spacing: 18) {
            Button {
                guard let place = foodPlaces.first else { return }
                completeSwipe(.save, place: place)
            } label: {
                Label(localized("Save", "收藏"), systemImage: "arrow.left")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(SaveAtlasPalette.coral)
            .disabled(foodPlaces.isEmpty || workingPlaceID != nil)
            .accessibilityIdentifier("origin.save")

            Button {
                guard let place = foodPlaces.first else { return }
                completeSwipe(.skip, place: place)
            } label: {
                Label(localized("Skip", "跳過"), systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
            .tint(SaveAtlasPalette.forest)
            .disabled(foodPlaces.isEmpty || workingPlaceID != nil)
            .accessibilityIdentifier("origin.skip")
        }
    }

    private var foodPlaces: [Place] {
        places.filter { place in
            place.socialSignal != nil && [.food, .cafe, .bar].contains(place.category)
        }
    }

    private func swipeGesture(for place: Place) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard workingPlaceID == nil else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                let decision = OriginSwipeDecision.resolve(translation: value.translation.width)
                guard decision != .none else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        dragOffset = .zero
                    }
                    return
                }
                completeSwipe(decision, place: place)
            }
    }

    private func completeSwipe(_ decision: OriginSwipeDecision, place: Place) {
        guard workingPlaceID == nil else { return }
        workingPlaceID = place.id
        withAnimation(.easeIn(duration: 0.2)) {
            dragOffset.width = decision == .save ? -520 : 520
        }

        Task {
            do {
                try await Task.sleep(for: .milliseconds(210))
                if decision == .save {
                    try await onSave(place)
                } else {
                    try await onSkip(place)
                }
                dragOffset = .zero
                workingPlaceID = nil
            } catch {
                dragOffset = .zero
                workingPlaceID = nil
                actionError = error.localizedDescription
            }
        }
    }

    private var atlasPresentation: AtlasPresentation {
        var presentation = AtlasPresentation.reference
        presentation.onOpenPassport = onOpenPassport
        return presentation
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.language.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

enum OriginSwipeDecision: Equatable {
    case save
    case skip
    case none

    static func resolve(translation: CGFloat, threshold: CGFloat = 82) -> OriginSwipeDecision {
        if translation <= -threshold { return .save }
        if translation >= threshold { return .skip }
        return .none
    }
}

private extension String {
    var originNonEmpty: String? { isEmpty ? nil : self }
}

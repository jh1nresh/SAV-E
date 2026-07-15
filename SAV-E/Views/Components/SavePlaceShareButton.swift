import SwiftUI

struct SavePlaceShareContent {
    let subject: String
    let fallbackURL: URL?
    let fallbackText: String
    let payload: SharedPlaceData?
    let sourcePlaceId: UUID?
    let optionalShareNote: String?

    var cacheKey: String {
        cacheKey(includingOptionalNote: false)
    }

    var stateKey: String {
        cacheKey(includingOptionalNote: true)
    }

    func cacheKey(includingOptionalNote: Bool) -> String {
        guard let payload = payload(includingOptionalNote: includingOptionalNote),
              let data = try? JSONEncoder().encode(payload)
        else { return fallbackText }
        return "\(sourcePlaceId?.uuidString ?? "unverified")|\(data.base64EncodedString())"
    }

    func payload(includingOptionalNote: Bool) -> SharedPlaceData? {
        guard let payload else { return nil }
        guard includingOptionalNote else { return payload }
        return payload.withShareNote(optionalShareNote)
    }

    func fallbackURL(includingOptionalNote: Bool) -> URL? {
        guard includingOptionalNote else { return fallbackURL }
        return payload(includingOptionalNote: true)?.toURL()
    }

    func message(for url: URL?, includingOptionalNote: Bool = false) -> String {
        guard let fallbackURL, let url else { return fallbackText }
        var message = fallbackText.replacingOccurrences(of: fallbackURL.absoluteString, with: url.absoluteString)
        if includingOptionalNote, let optionalShareNote {
            message += "\nWhy I'm sharing: \(optionalShareNote)"
        }
        return message
    }

    static func place(_ place: Place) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: place.shareSubject,
            fallbackURL: place.saveShareURL,
            fallbackText: place.shareText,
            payload: SharedPlaceData.from(place: place),
            sourcePlaceId: place.id,
            optionalShareNote: ShareRoutePayloadSanitizer.publicNote(place.note)
        )
    }

    static func mapCandidate(_ candidate: SaveMapCandidate) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: candidate.shareSubject,
            fallbackURL: candidate.saveShareURL,
            fallbackText: candidate.shareText,
            payload: SharedPlaceData.from(candidate: candidate),
            sourcePlaceId: nil,
            optionalShareNote: nil
        )
    }

    static func searchResult(_ result: SaveSearchResult) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: result.shareSubject,
            fallbackURL: result.saveShareURL,
            fallbackText: result.shareText,
            payload: SharedPlaceData.from(result: result),
            sourcePlaceId: nil,
            optionalShareNote: nil
        )
    }

    static func reviewCandidate(_ candidate: PlaceReviewCandidate) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: candidate.shareSubject,
            fallbackURL: candidate.saveShareURL,
            fallbackText: candidate.shareText,
            payload: SharedPlaceData.from(candidate: candidate),
            sourcePlaceId: nil,
            optionalShareNote: nil
        )
    }
}

struct SavePlaceShareButton<Label: View>: View {
    let content: SavePlaceShareContent
    @ViewBuilder var label: () -> Label

    @State private var shareURL: URL?
    @State private var noteShareURL: URL?
    @State private var basePreparationID: UUID?
    @State private var notePreparationID: UUID?
    @State private var activeContentKey: String
    @State private var isNoteComposerPresented = false
    @State private var includeOptionalNote = false

    init(content: SavePlaceShareContent, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
        _shareURL = State(initialValue: content.fallbackURL)
        _noteShareURL = State(initialValue: nil)
        _activeContentKey = State(initialValue: content.stateKey)
    }

    var body: some View {
        Group {
            if content.optionalShareNote != nil {
                Button {
                    isNoteComposerPresented = true
                } label: {
                    label()
                }
            } else if let shareURL {
                ShareLink(item: shareURL, subject: Text(content.subject), message: Text(content.message(for: shareURL))) {
                    label()
                }
            } else if content.payload != nil {
                Button {
                    Task {
                        await prepareShortLink()
                    }
                } label: {
                    label()
                        .opacity(isPreparing ? 0.56 : 1)
                }
                .disabled(isPreparing)
                .accessibilityLabel(isPreparing ? "Preparing share link" : "Create share link")
            } else {
                ShareLink(item: content.fallbackText, subject: Text(content.subject)) {
                    label()
                }
            }
        }
        .sheet(isPresented: $isNoteComposerPresented) {
            noteComposer
        }
        .task(id: content.stateKey) {
            resetForCurrentContent(content.stateKey)
            await prepareShortLink(includingOptionalNote: false)
        }
        .onChange(of: content.stateKey) { _, newKey in
            resetForCurrentContent(newKey)
        }
    }

    private var noteComposer: some View {
        NavigationStack {
            Form {
                if let optionalShareNote = content.optionalShareNote {
                    Section {
                        Text(optionalShareNote)
                            .foregroundStyle(.secondary)
                        Toggle("Include this note", isOn: $includeOptionalNote)
                    } header: {
                        Text("Your saved note")
                    } footer: {
                        Text("Your private note is excluded unless you turn this on.")
                    }
                }

                Section {
                    if let selectedURL = includeOptionalNote ? noteShareURL : shareURL {
                        ShareLink(
                            item: selectedURL,
                            subject: Text(content.subject),
                            message: Text(content.message(
                                for: selectedURL,
                                includingOptionalNote: includeOptionalNote
                            ))
                        ) {
                            SwiftUI.Label("Share now", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        HStack {
                            ProgressView()
                            Text("Preparing share link…")
                        }
                    }
                }
            }
            .navigationTitle("Share place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isNoteComposerPresented = false }
                }
            }
            .task(id: "\(includeOptionalNote):\(content.stateKey)") {
                await prepareShortLink(includingOptionalNote: includeOptionalNote)
            }
        }
        .presentationDetents([.medium])
    }

    private func prepareShortLink(includingOptionalNote: Bool = false) async {
        guard let payload = content.payload(includingOptionalNote: includingOptionalNote) else { return }
        let cacheKey = content.cacheKey(includingOptionalNote: includingOptionalNote)
        let contentKey = content.stateKey

        if let cached = await SavePlaceShareLinkCache.shared.url(for: cacheKey) {
            guard !Task.isCancelled, activeContentKey == contentKey else { return }
            setPreparedURL(cached, includingOptionalNote: includingOptionalNote)
            return
        }

        let preparationID = UUID()
        if includingOptionalNote {
            guard notePreparationID == nil else { return }
            notePreparationID = preparationID
        } else {
            guard basePreparationID == nil else { return }
            basePreparationID = preparationID
        }
        defer {
            if includingOptionalNote {
                if notePreparationID == preparationID { notePreparationID = nil }
            } else if basePreparationID == preparationID {
                basePreparationID = nil
            }
        }

        do {
            let url = try await SupabaseService.shared.createSharedPlaceLink(
                payload: payload,
                sourcePlaceId: content.sourcePlaceId,
                noteConsentVersion: includingOptionalNote ? 1 : nil
            )
            await SavePlaceShareLinkCache.shared.set(url, for: cacheKey)
            guard !Task.isCancelled, activeContentKey == contentKey else { return }
            setPreparedURL(url, includingOptionalNote: includingOptionalNote)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeContentKey == contentKey else { return }
            setPreparedURL(
                content.fallbackURL(includingOptionalNote: includingOptionalNote),
                includingOptionalNote: includingOptionalNote
            )
        }
    }

    private var isPreparing: Bool { basePreparationID != nil }

    private func setPreparedURL(_ url: URL?, includingOptionalNote: Bool) {
        if includingOptionalNote {
            noteShareURL = url
        } else {
            shareURL = url
        }
    }

    private func resetForCurrentContent(_ contentKey: String) {
        guard activeContentKey != contentKey else { return }
        activeContentKey = contentKey
        shareURL = content.fallbackURL
        noteShareURL = nil
        includeOptionalNote = false
        isNoteComposerPresented = false
        basePreparationID = nil
        notePreparationID = nil
    }
}

private actor SavePlaceShareLinkCache {
    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    static let shared = SavePlaceShareLinkCache()
    private var entries: [String: Entry] = [:]

    func url(for key: String) -> URL? {
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > Date() else {
            entries[key] = nil
            return nil
        }
        return entry.url
    }

    func set(_ url: URL, for key: String) {
        entries[key] = Entry(
            url: url,
            expiresAt: Date().addingTimeInterval(24 * 60 * 60)
        )
    }
}

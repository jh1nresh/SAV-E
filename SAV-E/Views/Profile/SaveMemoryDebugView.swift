import SwiftUI

struct SaveMemoryDebugView: View {
    @State private var records: [SaveMemoryRecord] = []
    @State private var preferences: [SaveMemoryPreference] = []
    @State private var errorMessage: String?
    @State private var editor: PreferenceEditorTarget?
    private let service: SupabaseServiceProtocol

    init(service: SupabaseServiceProtocol = SupabaseService.shared) {
        self.service = service
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if records.isEmpty && preferences.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "No Memory Yet",
                    systemImage: "tray",
                    description: Text("Save a place or add an explicit preference. SAV-E will not silently turn one action into a durable preference.")
                )
            }

            Section("Preferences") {
                ForEach(preferences.filter { $0.status == .active || $0.status == .proposed }) { preference in
                    preferenceRow(preference)
                }
            }

            Section("Place memory on this device") {
                ForEach(records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(record.displayTitle)
                            .font(.headline)
                            .foregroundColor(.saveInk)
                        Spacer()
                        Text(record.state.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.saveCocoa)
                    }

                    if let address = record.address {
                        Text(address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let sourceURL = record.sourceURL, let url = URL(string: sourceURL) {
                        Link(destination: url) {
                            Label("Open source", systemImage: "link")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.saveCocoa)
                        }
                    }

                    if let diagnostic = record.evidenceDiagnostic {
                        evidenceDiagnosticView(diagnostic)
                    } else if !record.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Evidence")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            EvidenceLinkList(evidence: record.evidence, maxItems: 3)
                        }
                    }

                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Memory & Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .new } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add preference")
            }
        }
        .sheet(item: $editor) { target in
            SavePreferenceEditor(target: target) { draft in
                await savePreference(target: target, draft: draft)
            }
        }
        .task { await loadMemory() }
        .refreshable { await loadMemory() }
    }

    @ViewBuilder
    private func preferenceRow(_ preference: SaveMemoryPreference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(preference.normalizedValue).font(.headline)
                Spacer()
                Text(preference.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveCocoa)
            }
            Text("\(preference.polarity.rawValue.capitalized) · \(preference.context) · \(preference.preferenceType)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(preference.source == .explicit
                 ? "Why: you explicitly added this preference."
                 : "Why: proposed from \(preference.evidenceCount) privacy-safe evidence reference\(preference.evidenceCount == 1 ? "" : "s").")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                if preference.status == .proposed {
                    Button("Confirm") { Task { await setStatus(.active, for: preference) } }
                    Button("Reject", role: .destructive) { Task { await setStatus(.removed, for: preference) } }
                } else {
                    Button("Correct") { editor = .edit(preference) }
                    Button("Remove", role: .destructive) { Task { await setStatus(.removed, for: preference) } }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("memory.preference.\(preference.id.uuidString)")
    }

    @MainActor
    private func loadMemory() async {
        do {
            records = try SaveLocalVaultService.shared.recentRecords(limit: 50)
            preferences = try await service.fetchMemoryPreferences()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func setStatus(_ status: SaveMemoryPreference.Status, for preference: SaveMemoryPreference) async {
        do {
            _ = try await service.updateMemoryPreference(preference.id, status: status)
            await loadMemory()
            NotificationCenter.default.post(name: .saveMemoryPreferencesDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func savePreference(target: PreferenceEditorTarget, draft: SaveMemoryPreferenceDraft) async -> Bool {
        do {
            switch target {
            case .new:
                _ = try await service.createMemoryPreference(draft)
            case .edit(let preference):
                _ = try await service.correctMemoryPreference(preference.id, draft: draft)
            }
            editor = nil
            await loadMemory()
            NotificationCenter.default.post(name: .saveMemoryPreferencesDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func evidenceDiagnosticView(_ diagnostic: SocialPlaceEvidenceDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(diagnostic.statusLabel)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.saveCocoa)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.saveCocoa.opacity(0.12))
                    .cornerRadius(999)
                Text(diagnostic.primaryActionLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }

            diagnosticSection("Found", items: diagnostic.found)
            diagnosticSection("Tried", items: diagnostic.attempts)
            diagnosticSection("Search next", items: diagnostic.suggestedSearchQueries ?? [])
            diagnosticSection("Missing", items: diagnostic.missingFields)

            if !diagnostic.nextBestClue.isEmpty {
                Text("Next best clue: \(diagnostic.nextBestClue)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveCocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.saveCocoa.opacity(0.08))
        .cornerRadius(12)
    }

    private func diagnosticSection(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !items.isEmpty {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                EvidenceLinkList(evidence: Array(items.prefix(3)), maxItems: 3)
            }
        }
    }
}

private enum PreferenceEditorTarget: Identifiable {
    case new
    case edit(SaveMemoryPreference)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let preference): return preference.id.uuidString
        }
    }
}

private struct SavePreferenceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let target: PreferenceEditorTarget
    let onSave: (SaveMemoryPreferenceDraft) async -> Bool
    @State private var type: String
    @State private var value: String
    @State private var context: String
    @State private var polarity: SaveMemoryPreference.Polarity
    @State private var isSaving = false

    init(target: PreferenceEditorTarget, onSave: @escaping (SaveMemoryPreferenceDraft) async -> Bool) {
        self.target = target
        self.onSave = onSave
        let preference: SaveMemoryPreference? = if case .edit(let value) = target { value } else { nil }
        _type = State(initialValue: preference?.preferenceType ?? "cuisine")
        _value = State(initialValue: preference?.normalizedValue ?? "")
        _context = State(initialValue: preference?.context ?? "general")
        _polarity = State(initialValue: preference?.polarity ?? .like)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Type (cuisine, item, price, vibe)", text: $type)
                TextField("Preference", text: $value)
                TextField("Context (general, work, travel…)", text: $context)
                Picker("Meaning", selection: $polarity) {
                    ForEach(SaveMemoryPreference.Polarity.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized).tag(value)
                    }
                }
                Section("Privacy") {
                    Text("SAV-E stores the normalized preference and concise evidence references—not your private note, message, or source payload.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(target.id == "new" ? "Add preference" : "Correct preference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            if await onSave(SaveMemoryPreferenceDraft(
                                preferenceType: type,
                                normalizedValue: value,
                                context: context,
                                polarity: polarity
                            )) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SaveMemoryDebugView()
    }
}

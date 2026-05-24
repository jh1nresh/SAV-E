import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showEditProfile = false
    @State private var draftDisplayName = ""
    var waitingClues: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PassportTopBar(
                        waitingClues: waitingClues,
                        onClose: { dismiss() },
                        onEdit: {
                            draftDisplayName = viewModel.profile.displayName
                            showEditProfile = true
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 16)

                    PassportHero(
                        profile: viewModel.profile,
                        onEdit: {
                            draftDisplayName = viewModel.profile.displayName
                            showEditProfile = true
                        }
                    )
                    .padding(.horizontal)

                    StatsView(profile: viewModel.profile, waitingClues: waitingClues)

                    if let errorMessage = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(errorMessage)
                                .lineLimit(2)
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(12)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    PassportStampSection(profile: viewModel.profile)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Passport Controls")
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveCocoa)
                            .padding(.horizontal, 4)

                        NavigationLink {
                            SaveMemoryDebugView()
                        } label: {
                            SettingsRow(icon: "tray.full", title: "Local Memory", color: .saveCocoa)
                        }
                        .buttonStyle(.plain)

                        SettingsRow(icon: "arrow.right.square", title: "Sign Out", color: .red) {
                            Task { await viewModel.signOut() }
                        }
                    }
                    .padding(12)
                    .saveNotebookPage(cornerRadius: 18)
                    .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
            .background(SaveDottedBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await viewModel.loadProfile()
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(
                displayName: $draftDisplayName,
                isSaving: viewModel.isSaving,
                errorMessage: viewModel.errorMessage,
                onCancel: { showEditProfile = false },
                onSave: {
                    let saved = await viewModel.updateDisplayName(draftDisplayName)
                    if saved { showEditProfile = false }
                }
            )
        }
    }
}

// MARK: - Edit Profile

private struct EditProfileSheet: View {
    @Binding var displayName: String
    let isSaving: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () async -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.black))
                            .foregroundColor(.saveInk)
                            .frame(width: 38, height: 38)
                            .background(Color.saveNotebookPage)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isSaving)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edit Passport")
                            .font(.title3.weight(.black))
                            .foregroundColor(.saveInk)
                        Text("This is how SAV-E labels your memory book.")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await onSave() }
                    } label: {
                        Text(isSaving ? "Saving..." : "Save")
                            .font(.caption.weight(.black))
                            .foregroundColor(.saveInk)
                            .padding(.horizontal, 13)
                            .frame(height: 38)
                            .background(Color.saveHoney)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
                            )
                    }
                    .disabled(isSaving)
                }
                .padding(.horizontal)
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 10) {
                    Text("PASSPORT NAME")
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveCocoa)

                    TextField("Name", text: $displayName)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.saveInk)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFocused)
                        .padding(14)
                        .background(Color.saveNotebookPage)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red)
                    } else {
                        Text("Email and sign-in provider stay managed by your login account.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .saveNotebookPage(cornerRadius: 20)
                .padding(.horizontal)

                Spacer()
            }
            .background(SaveDottedBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            isNameFocused = true
        }
    }
}

// MARK: - Passport

private struct PassportTopBar: View {
    let waitingClues: Int
    let onClose: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PassportIconButton(systemName: "xmark", action: onClose)

            VStack(alignment: .leading, spacing: 2) {
                Text("SAV-E Passport")
                    .font(.headline.weight(.black))
                    .foregroundColor(.saveInk)
                Text(waitingClues == 1 ? "1 clue waiting" : "\(waitingClues) clues waiting")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.black))
                    Text("Edit")
                        .font(.caption.weight(.black))
                }
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 11)
                        .frame(height: 38)
                        .background(Color.saveHoney)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 2)
                        )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.saveNotebookPage.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
    }
}

private struct PassportIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 38, height: 38)
                .background(Color.saveNotebookPage)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PassportHero: View {
    let profile: UserProfile
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PassportNotebookSpine(color: .saveNotebookSpine)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.saveHoney)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
                            )
                        Image(systemName: "passport.fill")
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(.saveInk)
                    }
                    .frame(width: 70, height: 78)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(.saveSuccess)
                            .background(Circle().fill(Color.saveNotebookPage))
                            .offset(x: 5, y: 5)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("SAV-E Passport")
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveCocoa)
                        Text(profile.displayName)
                            .font(.title2.weight(.black))
                            .foregroundColor(.saveInk)
                            .lineLimit(2)
                        Text(profile.email ?? "Local memory agent")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    PassportBadge(text: "MEMORY AGENT", color: .saveHoney)
                    PassportBadge(text: "REVIEW FIRST", color: .saveSignal)
                    Spacer()
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.black))
                            .foregroundColor(.saveInk)
                            .frame(width: 32, height: 32)
                            .background(Color.saveHoney)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit Passport")
                }
            }
            .padding(16)
        }
        .saveNotebookPage(cornerRadius: 22)
    }
}

private struct PassportNotebookSpine: View {
    var color: Color

    var body: some View {
        VStack(spacing: 11) {
            ForEach(0..<4, id: \.self) { _ in
                Circle()
                    .fill(Color.saveNotebookPage)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.saveCocoa.opacity(0.16), lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
        .frame(width: 24)
        .padding(.top, 18)
        .background(color.opacity(0.86))
    }
}

private struct PassportBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.38))
            .clipShape(Capsule())
    }
}

private struct PassportStampSection: View {
    let profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent stamps")
                    .font(.headline.weight(.black))
                    .foregroundColor(.saveInk)
                Spacer()
                Text(profile.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveCocoa)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.saveHoney.opacity(0.18))
                    .clipShape(Capsule())
            }

            if profile.collections.isEmpty {
                PassportStampRow(icon: "rectangle.stack.badge.plus", title: "No stamps yet", value: "Hatch a clue into your first memory card")
            } else {
                ForEach(profile.collections.prefix(3)) { collection in
                    PassportStampRow(
                        icon: "seal.fill",
                        title: collection.name,
                        value: "\(collection.placeIds.count) memory cards"
                    )
                }
            }

            PassportStampRow(icon: "calendar", title: "Joined", value: profile.createdAt.formatted(date: .abbreviated, time: .omitted))
        }
        .padding()
        .saveNotebookPage(cornerRadius: 18)
        .padding(.horizontal)
    }
}

private struct PassportStampRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.saveCocoa)
                .frame(width: 30, height: 30)
                .background(Color.saveHoney.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.saveInk)
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.saveInk)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
    }
}

#Preview {
    ProfileView()
}

import SwiftUI

/// Minimal cream palette for the extension so we don't pull in the app's
/// full theme stack (Color+Theme.swift references types outside this target).
private enum MessagesTheme {
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let card = Color(red: 1.0, green: 0.99, blue: 0.96)
    static let ink = Color(red: 0.16, green: 0.14, blue: 0.11)
    static let secondaryInk = Color(red: 0.42, green: 0.38, blue: 0.32)
    static let accent = Color(red: 0.78, green: 0.45, blue: 0.20)
    static let hairline = Color(red: 0.88, green: 0.84, blue: 0.76)
}

struct PlacePickerView: View {
    let places: [MessagesPlace]
    let onSelect: (MessagesPlace) -> Void

    var body: some View {
        ZStack {
            MessagesTheme.cream.ignoresSafeArea()

            if places.isEmpty {
                emptyState
            } else {
                placeList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(MessagesTheme.accent)
            Text("No saved places yet")
                .font(.headline)
                .foregroundStyle(MessagesTheme.ink)
            Text("Open SAV-E to save places first, then share them here.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(MessagesTheme.secondaryInk)
                .padding(.horizontal, 32)
        }
    }

    private var placeList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(places) { place in
                    Button {
                        onSelect(place)
                    } label: {
                        PlaceRow(place: place)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

private struct PlaceRow: View {
    let place: MessagesPlace

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(MessagesTheme.accent.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName(for: place.category))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MessagesTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MessagesTheme.ink)
                    .lineLimit(1)
                if !place.address.isEmpty {
                    Text(place.address)
                        .font(.system(size: 13))
                        .foregroundStyle(MessagesTheme.secondaryInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(MessagesTheme.accent.opacity(0.55))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MessagesTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MessagesTheme.hairline, lineWidth: 1)
        )
    }

    private func iconName(for category: String?) -> String {
        switch category?.lowercased() {
        case "food": return "fork.knife"
        case "cafe": return "cup.and.saucer.fill"
        case "bar": return "wineglass.fill"
        case "attraction": return "star.fill"
        case "stay": return "bed.double.fill"
        case "shopping": return "bag.fill"
        default: return "mappin.circle.fill"
        }
    }
}

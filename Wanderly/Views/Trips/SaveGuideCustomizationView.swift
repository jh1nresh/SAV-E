import SwiftUI

struct SaveGuideCustomizationView: View {
    let draft: SaveGuideCustomizationDraft
    var onCopyToTrips: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                guideStopsSection
                savedSwapsSection
                suggestionsSection
            }
            .padding(16)
        }
        .background(SaveDottedBackground())
        .navigationTitle("Guide draft")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.originalGuide.title)
                .font(.title3.weight(.black))
                .foregroundColor(.saveInk)
            if let creator = draft.originalGuide.creatorLabel {
                Text("By \(creator)")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveCocoa)
            }
            if let sourcePlatform = draft.originalGuide.sourcePlatform {
                Text("Source: \(sourcePlatform.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveMutedText)
            }
            Text(draft.explanation)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onCopyToTrips?()
            } label: {
                Label("Copy to my trips", systemImage: "plus.square.on.square")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.saveHoney)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .saveNotebookPage(cornerRadius: 18)
    }

    private var guideStopsSection: some View {
        section(title: "Guide stops") {
            ForEach(draft.keepStops) { stop in
                GuideStopRow(
                    title: stop.title,
                    subtitle: stop.address,
                    badge: stop.state.displayName,
                    systemImage: stop.state == .needsRecovery ? "exclamationmark.triangle" : "mappin.and.ellipse"
                )
            }
        }
    }

    private var savedSwapsSection: some View {
        section(title: "Map Stamps nearby") {
            if draft.swapInSavedPlaces.isEmpty {
                emptyLine("No Map Stamp swaps yet.")
            } else {
                ForEach(draft.swapInSavedPlaces) { stop in
                    GuideStopRow(
                        title: stop.title,
                        subtitle: stop.subtitle,
                        badge: "Map Stamp",
                        systemImage: "map.fill"
                    )
                }
            }
        }
    }

    private var suggestionsSection: some View {
        section(title: "New suggestions") {
            if draft.addNearbySuggestions.isEmpty {
                emptyLine("No unsaved suggestions attached.")
            } else {
                ForEach(draft.addNearbySuggestions) { stop in
                    GuideStopRow(
                        title: stop.title,
                        subtitle: stop.subtitle,
                        badge: "Unsaved suggestion",
                        systemImage: "sparkle.magnifyingglass"
                    )
                }
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.black))
                .foregroundColor(.saveInk)
            content()
        }
        .padding(12)
        .saveNotebookPage(cornerRadius: 16)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.saveMutedText)
    }
}

private struct GuideStopRow: View {
    let title: String
    let subtitle: String?
    let badge: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 30, height: 30)
                .background(Color.saveHoney)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.saveMutedText)
                        .lineLimit(2)
                }
                Text(badge)
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveCocoa)
            }
        }
    }
}

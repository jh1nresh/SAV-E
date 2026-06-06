import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Vision
import ImageIO

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: ShareExtensionView(
            extensionContext: extensionContext
        ))
        view.backgroundColor = .clear
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}

// MARK: - Parsed Place Model

struct ParsedPlace {
    var name: String
    var address: String
    var category: String
    var iconName: String
    var latitude: Double?
    var longitude: Double?
    var dishes: [String]
    var priceRange: String?
}

private enum SaveTheme {
    static let cream = Color(hex: "FFF5E7")
    static let yellow = Color(hex: "FFD66B")
    static let coral = Color(hex: "EE9C78")
    static let sky = Color(hex: "8FCAEA")
    static let mint = Color(hex: "C8EBCF")
    static let pink = Color(hex: "F6C1CB")
    static let ink = Color(hex: "3A2415")
    static let paper = Color(hex: "FFF0DC")
}

private struct ShareScrapbookBackground: View {
    var body: some View {
        SaveTheme.cream
            .overlay {
                Canvas { context, size in
                    let spacing: CGFloat = 18
                    for x in stride(from: CGFloat(8), through: size.width, by: spacing) {
                        for y in stride(from: CGFloat(8), through: size.height, by: spacing) {
                            let rect = CGRect(x: x, y: y, width: 2.2, height: 2.2)
                            context.fill(Path(ellipseIn: rect), with: .color(SaveTheme.ink.opacity(0.10)))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

private struct ShareStatusPill: View {
    var text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(SaveTheme.mint)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(SaveTheme.ink, lineWidth: 1))
            Text(text)
                .font(.caption.weight(.black))
                .foregroundColor(SaveTheme.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SaveTheme.yellow)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(SaveTheme.ink, lineWidth: 1.6))
        .shadow(color: SaveTheme.ink.opacity(0.14), radius: 0, x: 3, y: 3)
    }
}

private struct ShareBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.black))
            .foregroundColor(SaveTheme.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(SaveTheme.pink)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(SaveTheme.ink, lineWidth: 1.4)
            )
    }
}

private struct ShareScrapbookButton: View {
    var title: String
    var fill: Color
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.black))
                Text(title)
                    .font(.headline.weight(.black))
            }
            .foregroundColor(SaveTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SaveTheme.ink, lineWidth: 2)
            )
            .shadow(color: SaveTheme.ink.opacity(0.18), radius: 0, x: 4, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct ShareMiniSticker: View {
    var systemImage: String
    var fill: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .black))
            .foregroundColor(SaveTheme.ink)
            .frame(width: 42, height: 42)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SaveTheme.ink, lineWidth: 1.8)
            )
            .shadow(color: SaveTheme.ink.opacity(0.14), radius: 0, x: 3, y: 3)
    }
}

private struct ShareStickerStack: View {
    var category: String

    var body: some View {
        ZStack {
            ShareMiniSticker(systemImage: "sparkles", fill: SaveTheme.pink)
                .rotationEffect(.degrees(10))
                .offset(x: -34, y: 6)
            ShareMiniSticker(systemImage: iconName, fill: SaveTheme.yellow)
                .rotationEffect(.degrees(-8))
            ShareMiniSticker(systemImage: "mappin.and.ellipse", fill: SaveTheme.sky)
                .scaleEffect(0.82)
                .rotationEffect(.degrees(12))
                .offset(x: 31, y: 28)
        }
        .frame(width: 92, height: 82)
    }

    private var iconName: String {
        switch category {
        case "cafe": return "cup.and.saucer.fill"
        case "bar": return "wineglass.fill"
        case "attraction": return "star.fill"
        case "stay": return "bed.double.fill"
        case "shopping": return "bag.fill"
        default: return "fork.knife"
        }
    }
}

private struct ShareEvidenceReceipt: View {
    var candidate: PendingReviewCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Evidence")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(SaveTheme.ink)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundColor(SaveTheme.ink.opacity(0.60))
            }

            ShareEvidenceRow(text: "Source saved", isComplete: candidate.sourceURL != nil)
            ShareEvidenceRow(text: "Place name detected", isComplete: !candidate.candidateName.isEmpty && !candidate.isSourceOnly)
            ShareEvidenceRow(text: candidate.address.isEmpty ? "Address still needed" : "Address found", isComplete: !candidate.address.isEmpty)
        }
        .padding(14)
        .background(SaveTheme.paper.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SaveTheme.ink, lineWidth: 1.8)
        )
        .shadow(color: SaveTheme.ink.opacity(0.12), radius: 0, x: 4, y: 4)
    }
}

private struct ShareEvidenceRow: View {
    var text: String
    var isComplete: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dashed")
                .font(.caption.weight(.black))
                .foregroundColor(SaveTheme.ink)
                .frame(width: 18)
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundColor(SaveTheme.ink.opacity(0.78))
            Spacer()
        }
    }
}

private struct ShareCheckingStepRow: View {
    var systemImage: String
    var title: String
    var subtitle: String
    var fill: Color
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 11) {
            ShareFlatSticker(systemImage: systemImage, fill: fill)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(SaveTheme.ink)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(SaveTheme.ink.opacity(0.66))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isActive {
                ProgressView()
                    .tint(SaveTheme.ink)
                    .scaleEffect(0.82)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(SaveTheme.ink)
            }
        }
        .padding(10)
        .background(SaveTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SaveTheme.ink, lineWidth: 1.6)
        )
    }
}

private struct ShareFlatSticker: View {
    var systemImage: String
    var fill: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .black))
            .foregroundColor(SaveTheme.ink)
            .frame(width: 40, height: 40)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SaveTheme.ink, lineWidth: 1.6)
            )
    }
}

private struct ShareCaptureFooter: View {
    var text: String = "SAV-E Review · Open the app to finish"

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.caption.weight(.black))
            Text(text)
                .font(.caption.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.black))
        }
        .foregroundColor(SaveTheme.ink)
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(SaveTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SaveTheme.ink, lineWidth: 1.8)
        )
    }
}

private struct PendingSharedPlace: Codable {
    var name: String
    var address: String
    var category: String
    var latitude: Double
    var longitude: Double
    var dishes: [String]
    var priceRange: String?
    var sourceURL: String?
    var sourceText: String?
    var savedAt: Date
}

private struct ShareMetadata {
    var resolvedURL: String?
    var title: String?
    var description: String?
    var imageURL: URL?
    var htmlText: String?
}

private let shareMetadataHTMLByteLimit = 2_000_000
private let sharedImageByteLimit = 12_000_000
private let sharedImageOCRLineLimit = 80

private struct SocialPlaceEvidenceDiagnostic: Codable {
    var found: [String]
    var attempts: [String]
    var missingFields: [String]
    var nextBestClue: String
    var suggestedSearchQueries: [String]? = nil

    var statusLabel: String {
        if canSaveAsMapStamp { return "Map match ready" }
        if found.joined(separator: "\n").lowercased().contains("place-bearing source") { return "Place clue" }
        if lowercasedMissingFields.contains(where: { $0.contains("place name") }) { return "Source clue" }
        if lowercasedMissingFields.contains(where: { $0.contains("address") || $0.contains("coordinates") }) { return "Needs confirmation" }
        return "Review candidate"
    }

    var primaryActionLabel: String {
        if canSaveAsMapStamp { return "Confirm map match" }
        if statusLabel == "Place clue" { return "Run recovery search" }
        if statusLabel == "Source clue" { return "Add caption / screenshot / map link" }
        if lowercasedMissingFields.contains(where: { $0.contains("address") || $0.contains("coordinates") }) { return "Confirm address / coordinates" }
        return "Review evidence"
    }

    var canSaveAsMapStamp: Bool {
        let foundText = found.joined(separator: "\n").lowercased()
        return foundText.contains("google places match") &&
            foundText.contains("verified coordinates") &&
            !lowercasedMissingFields.contains(where: { $0.contains("coordinate") })
    }

    private var lowercasedMissingFields: [String] {
        missingFields.map { $0.lowercased() }
    }
}

private struct PendingReviewCandidate: Codable {
    var candidateName: String
    var address: String
    var category: String
    var sourceURL: String?
    var sourceText: String?
    var evidence: [String]
    var confidence: Double
    var missingInfo: [String]
    var savedAt: Date
    var evidenceDiagnostic: SocialPlaceEvidenceDiagnostic? = nil
    var isSourceOnly: Bool = false
    var reviewState: String? = nil

    var isPlaceBearingSource: Bool {
        reviewState == "place_bearing_source"
    }

    var isUnresolvedPlaceCandidate: Bool {
        reviewState == "unresolved_place_candidate"
    }
}

private struct ShareMemoryRecord: Codable {
    var id: UUID
    var state: String
    var sourceURL: String?
    var sourceText: String?
    var title: String
    var placeName: String?
    var address: String?
    var evidence: [String]
    var evidenceDiagnostic: SocialPlaceEvidenceDiagnostic? = nil
    var createdAt: Date
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    weak var extensionContext: NSExtensionContext?
    @State private var sharedURL: String = ""
    @State private var sharedText: String = ""
    @State private var sharedTitle: String = ""
    @State private var parsedPlace: ParsedPlace?
    @State private var reviewCandidate: PendingReviewCandidate?
    @State private var reviewCandidates: [PendingReviewCandidate] = []
    @State private var isParsing = true
    @State private var isSaved = false
    @State private var savedReviewCandidateCount: Int?
    @State private var parseError: String?
    @State private var selectedCategory: String = "food"

    private let categories = ["food", "cafe", "bar", "attraction", "stay", "shopping"]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if isParsing {
                    checkingPlaceCluesView
                } else if isSaved {
                    savedConfirmationView
                } else if let error = parseError {
                    VStack(spacing: 16) {
                        Text("🧸")
                            .font(.system(size: 46))
                        Text("SAV-E needs one more clue")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(SaveTheme.ink)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(SaveTheme.ink)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                        Text("Try sharing a map link, a clearer caption, or a frame with the place name.")
                            .font(.caption)
                            .foregroundColor(SaveTheme.ink)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(SaveTheme.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(SaveTheme.ink, lineWidth: 2)
                    )
                    .cornerRadius(28)
                    .shadow(color: SaveTheme.ink.opacity(0.16), radius: 0, x: 5, y: 5)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 20)
                } else if !reviewCandidates.isEmpty {
                    reviewCandidatesPreview(reviewCandidates)
                } else if let candidate = reviewCandidate {
                    reviewCandidatesPreview([candidate])
                } else if let place = parsedPlace {
                    placePreview(place)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShareScrapbookBackground().ignoresSafeArea())
            .navigationTitle("SAV-E ✨")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        extensionContext?.cancelRequest(withError: NSError(domain: "com.save", code: 0))
                    }
                }
            }
        }
        .background(ShareScrapbookBackground().ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await extractAndParse()
        }
    }

    private var checkingPlaceCluesView: some View {
        VStack(spacing: 14) {
            HStack {
                Text("SAV-E ✨")
                    .font(.title3.weight(.black))
                    .foregroundColor(SaveTheme.ink)
                Spacer()
                ShareStatusPill(text: "Checking place clues")
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ShareFlatSticker(systemImage: "magnifyingglass", fill: SaveTheme.yellow)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reading the shared post")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(SaveTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("SAV-E is looking for a real place name before it creates a review card.")
                            .font(.subheadline)
                            .foregroundColor(SaveTheme.ink.opacity(0.76))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ShareBadge(text: "No map pin until the place is confirmed")

                VStack(spacing: 9) {
                    ShareCheckingStepRow(
                        systemImage: "link",
                        title: "Source received",
                        subtitle: "The shared link is saved as evidence.",
                        fill: SaveTheme.sky
                    )
                    ShareCheckingStepRow(
                        systemImage: "text.magnifyingglass",
                        title: "Finding place names",
                        subtitle: "Captions, handles, and visible clues are being checked.",
                        fill: SaveTheme.pink,
                        isActive: true
                    )
                    ShareCheckingStepRow(
                        systemImage: "rectangle.stack.badge.plus",
                        title: "Review Candidate next",
                        subtitle: "Possible places wait in Review before saving.",
                        fill: SaveTheme.mint
                    )
                }
            }
            .padding(18)
            .background(SaveTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(SaveTheme.ink, lineWidth: 2.4)
            )

            Spacer(minLength: 8)

            ShareCaptureFooter()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var savedConfirmationView: some View {
        VStack(spacing: 14) {
            ShareStatusPill(text: savedReviewCandidateCount == nil ? "Map Stamp saved" : "Added to Review")

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ShareMiniSticker(
                        systemImage: savedReviewCandidateCount == nil ? "checkmark.seal.fill" : "tray.and.arrow.down.fill",
                        fill: savedReviewCandidateCount == nil ? SaveTheme.mint : SaveTheme.yellow
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(savedConfirmationTitle)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(SaveTheme.ink)
                            .lineLimit(2)

                        Text(savedConfirmationSubtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(SaveTheme.ink.opacity(0.70))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ShareEvidenceRow(text: "Source saved", isComplete: true)
                    ShareEvidenceRow(text: savedReviewCandidateCount == nil ? "Map pin ready" : "Waiting in Review", isComplete: true)
                    ShareEvidenceRow(text: "Open SAV-E to confirm", isComplete: savedReviewCandidateCount != nil)
                }
                .padding(12)
                .background(SaveTheme.yellow.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(SaveTheme.ink, style: StrokeStyle(lineWidth: 1.4, dash: [4]))
                )

                Text("Closing in a moment...")
                    .font(.caption.weight(.black))
                    .foregroundColor(SaveTheme.ink.opacity(0.58))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(18)
            .background(SaveTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(SaveTheme.ink, lineWidth: 2.4)
            )

            Spacer(minLength: 8)

            ShareCaptureFooter()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var savedConfirmationTitle: String {
        guard let count = savedReviewCandidateCount else {
            return "Saved to SAV-E"
        }
        return count == 1 ? "Review Candidate added" : "\(count) Review Candidates added"
    }

    private var savedConfirmationSubtitle: String {
        guard let count = savedReviewCandidateCount else {
            return "Open the app to see it on your map."
        }
        return count == 1
            ? "It will wait in SAV-E Review before becoming a Map Stamp."
            : "They will wait in SAV-E Review before becoming Map Stamps."
    }

    // MARK: - Place Preview

    private func placePreview(_ place: ParsedPlace) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SAV-E ✨")
                    .font(.title3.weight(.black))
                    .foregroundColor(SaveTheme.ink)
                Spacer()
                ShareStatusPill(text: "Map Stamp ready")
            }

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name)
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .foregroundColor(SaveTheme.ink)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(place.address.isEmpty ? "Address confirmed from source" : place.address)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(SaveTheme.ink.opacity(0.68))

                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption.weight(.black))
                            Text("Ready to save as a Map Stamp")
                                .font(.caption.weight(.black))
                        }
                        .foregroundColor(SaveTheme.ink)
                    }

                    if !place.dishes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(place.dishes, id: \.self) { dish in
                                    Text(dish)
                                        .font(.caption.weight(.black))
                                        .foregroundColor(SaveTheme.ink)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(SaveTheme.pink)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(SaveTheme.ink, lineWidth: 1.2))
                                }
                            }
                        }
                    }

                    Text("Category")
                        .font(.caption.weight(.black))
                        .foregroundColor(SaveTheme.ink.opacity(0.72))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { cat in
                                Button(action: { selectedCategory = cat }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: iconForCategory(cat))
                                            .font(.caption2.weight(.black))
                                        Text(cat.capitalized)
                                    }
                                    .font(.caption.weight(.black))
                                    .foregroundColor(SaveTheme.ink)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(cat == selectedCategory ? SaveTheme.yellow : SaveTheme.cream)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(SaveTheme.ink, lineWidth: 1.4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ShareScrapbookButton(title: "Save Map Stamp", fill: SaveTheme.yellow, systemImage: "checkmark.seal.fill", action: savePlace)
                        .padding(.top, 2)
                }
                .padding(18)
                .background(SaveTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(SaveTheme.ink, lineWidth: 2.4)
                )
                .shadow(color: SaveTheme.ink.opacity(0.18), radius: 0, x: 6, y: 6)

                ShareStickerStack(category: selectedCategory)
                    .offset(x: -12, y: -16)
            }

            Spacer(minLength: 8)

            ShareCaptureFooter()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func reviewCandidatesPreview(_ candidates: [PendingReviewCandidate]) -> some View {
        let primaryCandidate = candidates.first

        return VStack(spacing: 14) {
            HStack {
                Text("SAV-E ✨")
                    .font(.title3.weight(.black))
                    .foregroundColor(SaveTheme.ink)
                Spacer()
            }
            .padding(.top, 2)

            if let candidate = primaryCandidate, candidates.count == 1 {
                singleCandidateResult(candidate)
            } else {
                multipleCandidatesResult(candidates)
            }

            Spacer(minLength: 8)

            ShareCaptureFooter()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func singleCandidateResult(_ candidate: PendingReviewCandidate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ShareStatusPill(text: candidate.isSourceOnly ? "More clues needed" : "Possible place found")

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(candidate.candidateName)
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .foregroundColor(SaveTheme.ink)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(candidateLocationSubtitle(candidate))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(SaveTheme.ink.opacity(0.68))

                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.caption.weight(.black))
                            Text(sourceLine(candidate))
                                .font(.caption.weight(.black))
                        }
                        .foregroundColor(SaveTheme.ink)
                    }

                    ShareBadge(text: candidate.address.isEmpty ? "Almost ready · 1 clue missing" : "Ready to review")

                    Text(candidateExplanation(candidate))
                        .font(.subheadline)
                        .lineSpacing(3)
                        .foregroundColor(SaveTheme.ink.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        ShareScrapbookButton(title: "Confirm this place", fill: SaveTheme.yellow, systemImage: "checkmark.seal.fill", action: saveReviewCandidates)
                        ShareScrapbookButton(title: "Find address", fill: SaveTheme.sky, systemImage: "magnifyingglass", action: saveReviewCandidates)

                        Button("Keep as Source Clue", action: saveReviewCandidates)
                            .font(.caption.weight(.black))
                            .foregroundColor(SaveTheme.ink.opacity(0.72))
                            .padding(.top, 2)
                    }
                    .padding(.top, 2)
                }
                .padding(18)
                .background(SaveTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(SaveTheme.ink, lineWidth: 2.4)
                )
                .shadow(color: SaveTheme.ink.opacity(0.18), radius: 0, x: 6, y: 6)

                ShareStickerStack(category: candidate.category)
                    .offset(x: -12, y: -16)
            }

            ShareEvidenceReceipt(candidate: candidate)
        }
    }

    private func multipleCandidatesResult(_ candidates: [PendingReviewCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            ShareStatusPill(text: "\(candidates.count) possible places found")

            VStack(alignment: .leading, spacing: 12) {
                Text("Pick the place clue to save")
                    .font(.title3.weight(.black))
                    .foregroundColor(SaveTheme.ink)

                Text("SAV-E found a few possible places. They will wait in Review before becoming map pins.")
                    .font(.subheadline)
                    .foregroundColor(SaveTheme.ink.opacity(0.76))

                ForEach(Array(candidates.prefix(4).enumerated()), id: \.offset) { _, candidate in
                    Button {
                        saveReviewCandidates([candidate])
                    } label: {
                        HStack(spacing: 10) {
                            ShareMiniSticker(systemImage: iconForCategory(candidate.category), fill: SaveTheme.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.candidateName)
                                    .font(.subheadline.weight(.black))
                                    .foregroundColor(SaveTheme.ink)
                                    .lineLimit(2)
                                Text(candidate.address.isEmpty ? "Address still needed" : candidate.address)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(SaveTheme.ink.opacity(0.62))
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text("Add")
                                .font(.caption.weight(.black))
                                .foregroundColor(SaveTheme.ink)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(SaveTheme.mint)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(SaveTheme.ink, lineWidth: 1.2))
                        }
                        .padding(10)
                        .background(SaveTheme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(SaveTheme.ink, lineWidth: 1.6)
                        )
                    }
                    .buttonStyle(.plain)
                }

                ShareScrapbookButton(title: "Add all \(candidates.count) to Review", fill: SaveTheme.yellow, systemImage: "tray.and.arrow.down.fill", action: saveReviewCandidates)
            }
            .padding(16)
            .background(SaveTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(SaveTheme.ink, lineWidth: 2.4)
            )
            .shadow(color: SaveTheme.ink.opacity(0.18), radius: 0, x: 6, y: 6)
        }
    }

    private func candidateLocationSubtitle(_ candidate: PendingReviewCandidate) -> String {
        if !candidate.address.isEmpty { return candidate.address }
        let cityHint = candidate.evidence
            .compactMap { evidenceCityHint(from: $0) }
            .first
        return cityHint ?? "Needs exact address"
    }

    private func evidenceCityHint(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("shilin") || text.contains("士林") { return "Taipei · near Shilin Station" }
        if lower.contains("taipei") || text.contains("台北") { return "Taipei" }
        return nil
    }

    private func sourceLine(_ candidate: PendingReviewCandidate) -> String {
        guard let sourceURL = candidate.sourceURL?.lowercased() else { return "Found from shared post" }
        if sourceURL.contains("instagram.com") { return "Found from Instagram source" }
        if sourceURL.contains("tiktok.com") { return "Found from TikTok" }
        if sourceURL.contains("xiaohongshu.com") || sourceURL.contains("xhslink.com") { return "Found from Xiaohongshu" }
        if sourceURL.contains("douyin.com") || sourceURL.contains("iesdouyin.com") { return "Found from Douyin" }
        if sourceURL.contains("pin.it") || sourceURL.contains("pinterest.") { return "Found from Pinterest" }
        return "Found from shared link"
    }

    private func candidateExplanation(_ candidate: PendingReviewCandidate) -> String {
        if candidate.address.isEmpty {
            return "I found the likely place, but I still need the exact address before saving it as a map pin."
        }
        return "I found a likely place with an address. Confirm it before SAV-E saves it as a Map Stamp."
    }

    private func candidateSubtitle(_ candidates: [PendingReviewCandidate]) -> String {
        guard candidates.count == 1, let candidate = candidates.first else {
            return "Review each candidate in SAV-E before saving."
        }
        if candidate.isUnresolvedPlaceCandidate { return "Review Candidate from shared source" }
        if candidate.isSourceOnly { return "Saved as a source clue, not a map pin yet" }
        if candidate.isPlaceBearingSource { return "Needs exact venue before Map Stamp" }
        return candidate.address.isEmpty ? "Needs address confirmation" : candidate.address
    }

    private func candidateIntro(_ candidates: [PendingReviewCandidate]) -> String {
        guard candidates.count == 1, let candidate = candidates.first else {
            return "SAV-E found a few place clues. Review the evidence before saving."
        }
        if candidate.isSourceOnly {
            return "SAV-E found the source, but not enough place evidence yet. It will keep this as a clue and show exactly what is missing."
        }
        if candidate.isUnresolvedPlaceCandidate {
            return "SAV-E found a possible place. It still needs an address or Google Places match before saving this as a Map Stamp."
        }
        if candidate.isPlaceBearingSource {
            return "This looks place-related, but SAV-E still needs the exact venue before it can save a Map Stamp."
        }
        return "SAV-E found a place clue. Check the evidence before saving."
    }

    private func candidateActionTitle(_ candidate: PendingReviewCandidate) -> String {
        if candidate.isSourceOnly { return "Save Source Clue" }
        if candidate.isUnresolvedPlaceCandidate { return "Add Review Candidate" }
        return "Add to Review"
    }

    private func reviewCandidatesHeading(_ candidates: [PendingReviewCandidate]) -> String {
        guard candidates.count == 1, let candidate = candidates.first else {
            return "Place clues found"
        }
        if candidate.isUnresolvedPlaceCandidate { return "Review Candidate found" }
        if candidate.isSourceOnly { return "Source clue saved" }
        if candidate.isPlaceBearingSource {
            return candidate.category == "food" || candidate.category == "cafe"
                ? "Restaurant clue found"
                : "Place clue found"
        }
        return "Place clue found"
    }

    private func shareEvidenceDiagnosticView(_ diagnostic: SocialPlaceEvidenceDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(diagnostic.statusLabel)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(SaveTheme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(SaveTheme.paper)
                    .cornerRadius(999)
                Text(diagnostic.primaryActionLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(SaveTheme.ink)
                Spacer()
            }

            shareDiagnosticSection("Found", items: diagnostic.found)
            shareDiagnosticSection("Tried", items: diagnostic.attempts)
            shareDiagnosticSection("Search next", items: diagnostic.suggestedSearchQueries ?? [])
            shareDiagnosticSection("Missing", items: diagnostic.missingFields)

            if !diagnostic.nextBestClue.isEmpty {
                Text("Next best clue: \(diagnostic.nextBestClue)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(SaveTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(SaveTheme.pink.opacity(0.6))
        .cornerRadius(16)
    }

    private func shareDiagnosticSection(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !items.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                ForEach(items.prefix(3), id: \.self) { item in
                    Text("• \(item)")
                        .font(.caption)
                        .foregroundColor(SaveTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Extract & Parse

    private func extractAndParse() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            parseError = "No content to parse"
            isParsing = false
            return
        }

        var extractedImageData: Data?

        // Extract URL, text, or screenshot image.
        for item in items {
            if let title = item.attributedTitle?.string, !title.isEmpty {
                sharedTitle = title
            }
            if let text = item.attributedContentText?.string, !text.isEmpty, sharedText.isEmpty {
                sharedText = text
            }

            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        sharedURL = url.absoluteString
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.text.identifier) as? String {
                        sharedText = text
                    }
                }
                if extractedImageData == nil,
                   attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                   let imageData = await sharedImageData(from: attachment) {
                    extractedImageData = imageData
                }
            }
        }

        let content = sharedURL.isEmpty ? sharedText : sharedURL
        if let imageData = extractedImageData, sharedURL.isEmpty {
            let candidates = await sharedImageReviewCandidates(
                from: imageData,
                sharedTitle: sharedTitle,
                sharedText: sharedText
            )
            if !candidates.isEmpty {
                reviewCandidates = candidates
                selectedCategory = reviewCandidates.first?.category ?? "food"
                isParsing = false
                return
            }
            parseError = "SAV-E could not read enough place text from this screenshot. Try sharing a clearer screenshot, caption, or map link."
            isParsing = false
            return
        }

        guard !content.isEmpty else {
            parseError = "No URL or text found in shared content"
            isParsing = false
            return
        }

        let metadata = await shareMetadata(from: sharedURL)
        let parseContent = metadata.resolvedURL.flatMap { $0.isEmpty ? nil : $0 } ?? content

        if GoogleMapsListPlaceExtractor.looksLikeGoogleMapsList(
            sourceURL: parseContent,
            title: sharedTitle,
            text: sharedText,
            metadataTitle: metadata.title,
            metadataDescription: metadata.description
        ) {
            let listCandidates = googleMapsListReviewCandidates(
                from: metadata,
                sourceURLString: parseContent,
                sharedTitle: sharedTitle,
                sharedText: sharedText
            )
            if !listCandidates.isEmpty {
                reviewCandidates = listCandidates
                selectedCategory = reviewCandidates.first?.category ?? "food"
                isParsing = false
                return
            }
            let sourceOnly = googleMapsListSourceOnlyReviewCandidate(
                from: metadata,
                sourceURLString: parseContent,
                sharedTitle: sharedTitle,
                sharedText: sharedText
            )
            reviewCandidates = [sourceOnly]
            selectedCategory = sourceOnly.category
            isParsing = false
            return
        }

        if let mapPlace = deterministicMapPlace(from: parseContent, title: sharedTitle, text: sharedText) {
            parsedPlace = mapPlace
            selectedCategory = mapPlace.category
            isParsing = false
            return
        }

        if let sourceURL = URL(string: parseContent),
           isSocialURL(sourceURL) {
            let candidates = await socialAnalysisReviewCandidates(
                from: metadata,
                sharedTitle: sharedTitle,
                sharedText: sharedText,
                sourceURLString: parseContent
            )
            if !candidates.isEmpty {
                reviewCandidates = candidates
                selectedCategory = reviewCandidates.first?.category ?? "stay"
                isParsing = false
                return
            }
            let sourceOnly = sourceOnlyReviewCandidate(sourceURLString: parseContent, evidenceText: publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText))
            reviewCandidates = [sourceOnly]
            selectedCategory = sourceOnly.category
            isParsing = false
            return
        }

        let aiContent = [sharedTitle, sharedText, metadata.title, metadata.description, parseContent]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        // Parse with Gemini only when the shared URL does not contain usable map coordinates.
        do {
            guard hasMeaningfulPlaceContext(aiContent, sourceURLString: parseContent) else {
                throw NSError(domain: "save", code: 4, userInfo: [NSLocalizedDescriptionKey: "Share a map link or a post with a visible place name so SAV-E does not guess the wrong city."])
            }
            let aiPlace = try await parseWithGemini(content: aiContent, sourceURLString: parseContent)
            if hasReliableCoordinates(aiPlace) {
                parsedPlace = aiPlace
                selectedCategory = aiPlace.category
            } else if let candidate = reviewCandidate(from: aiPlace, sourceURLString: parseContent, sourceText: aiContent) {
                reviewCandidate = candidate
                selectedCategory = candidate.category
            } else {
                throw NSError(domain: "save", code: 5, userInfo: [NSLocalizedDescriptionKey: "SAV-E could not identify one exact place from this post. Share the map link or include the place name."])
            }
        } catch {
            saveSourceOnlyMemory(parseContent, reason: error.localizedDescription)
            parseError = userFacingParseError(from: error)
        }
        isParsing = false
    }

    // MARK: - Gemini Parsing

    private func parseWithGemini(content: String, sourceURLString: String) async throws -> ParsedPlace {
        guard let apiKey = geminiAPIKey(), !apiKey.isEmpty else {
            throw NSError(domain: "save", code: 1, userInfo: [NSLocalizedDescriptionKey: "GEMINI_API_KEY not configured"])
        }

        let prompt = """
        Extract place information from this shared content. Respond ONLY with a valid JSON object, no markdown.

        Content: \(content)

        Response schema:
        {
          "name": "Place Name",
          "address": "Full address",
          "category": "food" | "cafe" | "bar" | "attraction" | "stay" | "shopping",
          "latitude": null,
          "longitude": null,
          "dishes": ["dish1", "dish2"],
          "priceRange": "$$",
          "needsReview": false
        }

        Rules:
        - Extract the place name, address, and category only from explicit text, metadata, or map URL data
        - If it's a restaurant/food URL, extract recommended dishes
        - Use null for latitude and longitude unless exact coordinates are explicitly present in the source or map URL
        - Do not guess a city, address, or coordinates from a social URL alone
        - If the source says Beijing/北京, do not return a Shanghai/上海 place, and vice versa
        - If you can identify a likely place but exact coordinates are missing, keep the place fields and set latitude/longitude to null with needsReview true
        - If you cannot identify one exact place, set needsReview to true and use null for missing fields
        - Never use a popular default city or a plausible replacement place
        - category must be one of: food, cafe, bar, attraction, stay, shopping
        """

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 512]
        ]

        let requestBody = try JSONSerialization.data(withJSONObject: body)
        var responseData: Data?
        var lastStatusCode = 0

        for model in SAVEProductionConfig.defaultGeminiModelFallbacks {
            let endpoint = SAVEProductionConfig.geminiGenerateContentURL(apiKey: apiKey, model: model)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestBody

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { continue }
            lastStatusCode = http.statusCode
            if http.statusCode == 200 {
                responseData = data
                break
            }
            if http.statusCode != 404 && http.statusCode != 429 {
                break
            }
        }

        guard let data = responseData else {
            throw NSError(domain: "save", code: lastStatusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini API error \(lastStatusCode)"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let responseContent = candidates.first?["content"] as? [String: Any],
              let parts = responseContent["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw NSError(domain: "save", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty AI response"])
        }

        // Parse JSON from response
        var jsonString = text
        if let start = text.range(of: "{"),
           let end = text.range(of: "}", options: .backwards),
           start.lowerBound < end.upperBound {
            jsonString = String(text[start.lowerBound..<end.upperBound])
        }
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "save", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't parse AI response"])
        }

        let place = ParsedPlace(
            name: dict["name"] as? String ?? "Unknown Place",
            address: dict["address"] as? String ?? "",
            category: dict["category"] as? String ?? "food",
            iconName: iconForCategory(dict["category"] as? String ?? "food"),
            latitude: dict["latitude"] as? Double,
            longitude: dict["longitude"] as? Double,
            dishes: dict["dishes"] as? [String] ?? [],
            priceRange: dict["priceRange"] as? String
        )
        try validateAIPlace(place, against: content, sourceURLString: sourceURLString)
        return place
    }

    private func shareMetadata(from urlString: String) async -> ShareMetadata {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            return ShareMetadata()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let resolvedURL = response.url?.absoluteString ?? url.absoluteString
            let html = String(data: data.prefix(shareMetadataHTMLByteLimit), encoding: .utf8) ?? ""
            return ShareMetadata(
                resolvedURL: resolvedURL,
                title: metadataValue(in: html, keys: ["og:title", "twitter:title", "title"]),
                description: metadataValue(in: html, keys: ["og:description", "twitter:description", "description"]),
                imageURL: metadataImageURL(in: html, baseURL: response.url ?? url),
                htmlText: html
            )
        } catch {
            return ShareMetadata(resolvedURL: url.absoluteString, title: nil, description: nil)
        }
    }

    private func metadataImageURL(in html: String, baseURL: URL) -> URL? {
        guard let imageValue = metadataValue(in: html, keys: ["og:image", "twitter:image", "image"]),
              let imageURL = URL(string: imageValue, relativeTo: baseURL)?.absoluteURL,
              imageURL.scheme?.hasPrefix("http") == true else {
            return nil
        }
        return imageURL
    }

    private func metadataImageData(from imageURL: URL) async -> Data? {
        var request = URLRequest(url: imageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= 2_000_000,
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func sharedImageData(from provider: NSItemProvider) async -> Data? {
        if let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) {
            if let data = item as? Data {
                return boundedSharedImageData(data)
            }
            if let image = item as? UIImage,
               let data = image.jpegData(compressionQuality: 0.88) {
                return boundedSharedImageData(data)
            }
            if let url = item as? URL,
               let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                return boundedSharedImageData(data)
            }
            if let url = item as? NSURL,
               let data = try? Data(contentsOf: url as URL, options: .mappedIfSafe) {
                return boundedSharedImageData(data)
            }
        }

        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data.flatMap(boundedSharedImageData))
            }
        }
    }

    private func boundedSharedImageData(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= sharedImageByteLimit else {
            return nil
        }
        return data
    }

    private func metadataValue(in html: String, keys: [String]) -> String? {
        guard !html.isEmpty else { return nil }

        for key in keys {
            if key == "title",
               let start = html.range(of: "<title", options: [.caseInsensitive]),
               let openEnd = html[start.upperBound...].range(of: ">"),
               let close = html[openEnd.upperBound...].range(of: "</title>", options: [.caseInsensitive]) {
                return cleanHTMLText(String(html[openEnd.upperBound..<close.lowerBound]))
            }

            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let patterns: [(pattern: String, valueCaptureIndex: Int)] = [
                (#"<meta[^>]+(?:property|name)=["']\#(escapedKey)["'][^>]+content=(["'])(.*?)\1[^>]*>"#, 2),
                (#"<meta[^>]+content=(["'])(.*?)\1[^>]+(?:property|name)=["']\#(escapedKey)["'][^>]*>"#, 2)
            ]

            for (pattern, valueCaptureIndex) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                guard let match = regex.firstMatch(in: html, range: range),
                      match.numberOfRanges > valueCaptureIndex,
                      let valueRange = Range(match.range(at: valueCaptureIndex), in: html) else {
                    continue
                }
                let value = cleanHTMLText(String(html[valueRange]))
                if !value.isEmpty { return value }
            }
        }

        return nil
    }

    private func cleanHTMLText(_ value: String) -> String {
        decodeNumericHTMLEntities(in: value)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#034;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t\f]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeNumericHTMLEntities(in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(x[0-9A-Fa-f]+|\d+);"#) else {
            return value
        }

        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
        var decoded = value

        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let entityRange = Range(match.range(at: 1), in: value),
                  let fullRange = Range(match.range, in: decoded) else {
                continue
            }

            let entity = String(value[entityRange])
            let codePoint: UInt32?
            if entity.lowercased().hasPrefix("x") {
                codePoint = UInt32(entity.dropFirst(), radix: 16)
            } else {
                codePoint = UInt32(entity)
            }

            guard let codePoint,
                  let scalar = UnicodeScalar(codePoint) else {
                continue
            }

            decoded.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        return decoded
    }

    private func googleMapsListReviewCandidates(
        from metadata: ShareMetadata,
        sourceURLString: String,
        sharedTitle: String,
        sharedText: String
    ) -> [PendingReviewCandidate] {
        let extracted = GoogleMapsListPlaceExtractor.extractCandidates(
            sourceURL: sourceURLString,
            title: sharedTitle,
            text: sharedText,
            metadataTitle: metadata.title,
            metadataDescription: metadata.description,
            htmlText: metadata.htmlText
        )
        guard !extracted.isEmpty else { return [] }

        let listTitle = [sharedTitle, metadata.title]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Google Maps saved list"
        let listEvidence = "Google Maps saved list: \(listTitle)"

        return extracted.prefix(30).map { place in
            let hasCoordinates = place.latitude != nil && place.longitude != nil
            let hasAddress = !place.address.isEmpty
            var evidence = [
                "Source URL: \(sourceURLString)",
                listEvidence,
                "Extracted from Google Maps list share"
            ]
            evidence.append(contentsOf: place.evidence)
            if hasCoordinates { evidence.append("Verified coordinates found in shared list HTML") }
            if hasAddress { evidence.append("Address found near list place: \(place.address)") }

            return PendingReviewCandidate(
                candidateName: place.name,
                address: place.address,
                category: fallbackCategory(from: [place.name, place.address, sharedText, metadata.description ?? ""].joined(separator: " ")),
                sourceURL: sourceURLString,
                sourceText: publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText),
                evidence: evidence,
                confidence: hasCoordinates ? 0.78 : (hasAddress ? 0.68 : 0.56),
                missingInfo: hasCoordinates ? [] : ["Confirm exact address / coordinates before saving as a Map Stamp"],
                savedAt: Date(),
                evidenceDiagnostic: SocialPlaceEvidenceDiagnostic(
                    found: evidence,
                    attempts: ["Scanned Google Maps saved-list share metadata/HTML for embedded place links"],
                    missingFields: hasCoordinates ? [] : ["coordinates", hasAddress ? "" : "address"].filter { !$0.isEmpty },
                    nextBestClue: hasCoordinates ? "Ready to confirm as a Map Stamp." : "Open the candidate or run Google Places match before saving this as a Map Stamp."
                ),
                isSourceOnly: false,
                reviewState: hasCoordinates ? "map_match_ready" : "google_maps_list_candidate"
            )
        }
    }

    private func googleMapsListSourceOnlyReviewCandidate(
        from metadata: ShareMetadata,
        sourceURLString: String,
        sharedTitle: String,
        sharedText: String
    ) -> PendingReviewCandidate {
        let listTitle = googleMapsListTitle(sharedTitle: sharedTitle, metadataTitle: metadata.title)
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        let evidence = [
            "Source URL: \(sourceURLString)",
            "Google Maps saved list: \(listTitle)",
            "No public place links were exposed in the shared list metadata/HTML"
        ]
        let diagnostic = SocialPlaceEvidenceDiagnostic(
            found: evidence,
            attempts: [
                "Scanned Google Maps saved-list metadata/HTML for /maps/place, /maps/search, and /maps?cid links",
                "Kept this as a source clue instead of inventing places from a private or short-link shell"
            ],
            missingFields: ["Public list entries", "Verified place name", "Verified address", "Verified coordinates"],
            nextBestClue: "Make the Google Maps list public/shared-readable, share an individual place, or share a screenshot/copied list text."
        )
        return PendingReviewCandidate(
            candidateName: listTitle,
            address: "",
            category: "attraction",
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: diagnostic.found + diagnostic.attempts + ["Next best clue: \(diagnostic.nextBestClue)"],
            confidence: 0,
            missingInfo: diagnostic.missingFields,
            savedAt: Date(),
            evidenceDiagnostic: diagnostic,
            isSourceOnly: true,
            reviewState: "google_maps_list_source_only"
        )
    }

    private func googleMapsListTitle(sharedTitle: String, metadataTitle: String?) -> String {
        let rawTitle = [sharedTitle, metadataTitle]
            .map { $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            .first(where: { !$0.isEmpty }) ?? "Google Maps saved list"
        let cleaned = rawTitle
            .replacingOccurrences(of: " - Google Maps", with: "")
            .replacingOccurrences(of: "| Google Maps", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Google Maps saved list" : cleaned
    }

    private func socialReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let handle = firstSocialHandle(in: evidenceText) else { return nil }

        let address = firstAddress(in: evidenceText) ?? locatedCity(in: evidenceText) ?? ""
        let resolved = SocialPlaceEvidenceScorer.resolvedDisplayName(fromSocialHandle: handle, evidenceText: evidenceText)
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty, isResolvedHandle: resolved.evidence != nil)
        let candidateName = resolved.name
        let category = fallbackCategory(from: evidenceText)
        var evidence = ["Instagram handle @\(handle)", "Evidence tier: \(tier.rawValue)"]
        if !sourceURLString.isEmpty {
            evidence.append("Source URL: \(sourceURLString)")
        }
        if let profileEvidence = resolved.evidence {
            evidence.append(profileEvidence)
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: candidateName,
            address: address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: min(0.58 + resolved.confidenceBoost, 0.85),
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func ocrFallbackReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) async -> PendingReviewCandidate? {
        guard let imageURL = metadata.imageURL,
              let imageData = await metadataImageData(from: imageURL) else { return nil }
        let ocrLines = await recognizedTextLines(from: imageData)
        guard let result = SocialOCRCandidateHeuristics.candidate(from: ocrLines) else { return nil }

        let captionText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        let ocrText = ocrLines.joined(separator: "\n")
        let combinedText = [sourceURLString, captionText, ocrText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let category = fallbackCategory(from: ([result.name, captionText, ocrText].joined(separator: "\n")))
        let tier: SocialPlaceEvidenceTier = .weakCandidate
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "OCR-derived candidate: \(result.name)"
        ]
        if !ocrText.isEmpty {
            evidence.append("OCR text: \(String(ocrText.prefix(300)))")
        }
        if !result.supportingLines.isEmpty {
            evidence.append("OCR supporting lines: \(result.supportingLines.joined(separator: " | "))")
        }

        return PendingReviewCandidate(
            candidateName: result.name,
            address: "",
            category: category,
            sourceURL: sourceURLString,
            sourceText: combinedText,
            evidence: evidence,
            confidence: result.confidence,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(
                tier: tier,
                hasAddress: false,
                source: "OCR-derived candidate; verify venue identity"
            ),
            savedAt: Date()
        )
    }

    private func recognizedTextLines(from imageData: Data) async -> [String] {
        guard let cgImage = downsampledCGImage(from: imageData) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations
                    .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private func downsampledCGImage(from imageData: Data, maxPixelSize: CGFloat = 1_024) -> CGImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions)
    }

    private func captionNamedSocialReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let name = bracketedPlaceName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? firstAddress(in: evidenceText) ?? ""
        let category = fallbackCategory(from: "\(name) \(evidenceText)")
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "Public metadata named place: \(name)"
        ]
        if !address.isEmpty {
            evidence.append("Location clue: \(address)")
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: address.isEmpty ? 0.5 : 0.62,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func captionVenueIntroReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let name = venueIntroName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? firstAddress(in: evidenceText) ?? ""
        let category = fallbackCategory(from: "\(name) \(evidenceText)")
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "Public metadata venue anchor: \(name)"
        ]
        if !address.isEmpty {
            evidence.append("Location clue: \(address)")
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: address.isEmpty ? 0.56 : 0.66,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func chineseSocialTitleReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let name = chineseVenueName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? firstAddress(in: evidenceText) ?? ""
        let category = fallbackCategory(from: "\(name) \(evidenceText)")
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "Public metadata named venue: \(name)"
        ]
        if !address.isEmpty {
            evidence.append("Location clue: \(address)")
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: address.isEmpty ? 0.56 : 0.66,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func captionLineSocialReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let inferred = inferredPlaceLineBeforeAddress(in: evidenceText) else { return nil }
        let category = fallbackCategory(from: "\(inferred.name) \(evidenceText)")
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: true)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "Public metadata place line: \(inferred.name)",
            "Location clue: \(inferred.address)"
        ]
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }
        return PendingReviewCandidate(
            candidateName: inferred.name,
            address: inferred.address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: 0.6,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: true),
            savedAt: Date()
        )
    }

    private func sharedImageReviewCandidates(
        from imageData: Data,
        sharedTitle: String,
        sharedText: String
    ) async -> [PendingReviewCandidate] {
        let ocrLines = Array(await recognizedTextLines(from: imageData).prefix(sharedImageOCRLineLimit))
        guard !ocrLines.isEmpty else { return [] }

        let ocrText = ocrLines.joined(separator: "\n")
        let evidenceText = [sharedTitle, sharedText, "Shared screenshot OCR:", ocrText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let parser = SocialPlaceParser()
        let analysis = parser.analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: "",
                resolvedURL: nil,
                sharedTitle: sharedTitle,
                sharedText: sharedText,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: ocrLines
            )
        )

        let candidates = analysis.placesFound.map { draft in
            var candidate = pendingReviewCandidate(
                from: draft,
                sourceURLString: "",
                sourceText: evidenceText,
                ocrLines: ocrLines
            )
            candidate.sourceURL = nil
            candidate.evidence = appendUniqueEvidence(
                candidate.evidence,
                [
                    "Input: shared screenshot",
                    "OCR text: \(String(ocrText.prefix(300)))"
                ]
            )
            return candidate
        }
        if !candidates.isEmpty {
            return rankedSocialAnalysisCandidates(candidates.map(markAsSocialAnalysisCandidate))
        }

        if let ocrCandidate = sharedImageOCRCandidate(from: ocrLines, evidenceText: evidenceText) {
            return [ocrCandidate]
        }

        if analysis.isPlaceBearing {
            var candidate = placeBearingSourceReviewCandidate(
                from: analysis,
                sourceURLString: "",
                evidenceText: evidenceText
            )
            candidate.sourceURL = nil
            candidate.evidence = appendUniqueEvidence(candidate.evidence, ["Input: shared screenshot"])
            return [candidate]
        }

        return [sharedImageSourceOnlyReviewCandidate(ocrText: ocrText, evidenceText: evidenceText)]
    }

    private func sharedImageOCRCandidate(
        from ocrLines: [String],
        evidenceText: String
    ) -> PendingReviewCandidate? {
        guard let result = SocialOCRCandidateHeuristics.candidate(from: ocrLines) else { return nil }
        let ocrText = ocrLines.joined(separator: "\n")
        let tier: SocialPlaceEvidenceTier = .weakCandidate
        var evidence = [
            "Input: shared screenshot",
            "Evidence tier: \(tier.rawValue)",
            "OCR-derived candidate: \(result.name)",
            "OCR text: \(String(ocrText.prefix(300)))"
        ]
        if !result.supportingLines.isEmpty {
            evidence.append("OCR supporting lines: \(result.supportingLines.joined(separator: " | "))")
        }

        return PendingReviewCandidate(
            candidateName: result.name,
            address: "",
            category: fallbackCategory(from: "\(result.name)\n\(evidenceText)"),
            sourceURL: nil,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: result.confidence,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(
                tier: tier,
                hasAddress: false,
                source: "OCR-derived screenshot candidate; verify venue identity"
            ),
            savedAt: Date()
        )
    }

    private func sharedImageSourceOnlyReviewCandidate(
        ocrText: String,
        evidenceText: String
    ) -> PendingReviewCandidate {
        let diagnostic = SocialPlaceEvidenceDiagnostic(
            found: appendUniqueEvidence(
                ["Input: shared screenshot"],
                ocrText.isEmpty ? [] : ["OCR text: \(String(ocrText.prefix(300)))"]
            ),
            attempts: [
                "Read the shared screenshot with on-device OCR",
                "Checked OCR text for explicit place names",
                "Kept this as a source-only clue instead of inventing a place"
            ],
            missingFields: ["Verified place name", "Verified address", "Verified coordinates"],
            nextBestClue: "Share a clearer screenshot, caption, or map link before saving as a Map Stamp."
        )
        return PendingReviewCandidate(
            candidateName: "Screenshot clue",
            address: "",
            category: fallbackCategory(from: ocrText),
            sourceURL: nil,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: diagnostic.found + diagnostic.attempts + ["Next best clue: \(diagnostic.nextBestClue)"],
            confidence: 0,
            missingInfo: diagnostic.missingFields,
            savedAt: Date(),
            evidenceDiagnostic: diagnostic,
            isSourceOnly: true
        )
    }

    private func socialAnalysisReviewCandidates(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) async -> [PendingReviewCandidate] {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        let parser = SocialPlaceParser()
        let textOnlyAnalysis = parser.analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: sourceURLString,
                resolvedURL: metadata.resolvedURL,
                sharedTitle: sharedTitle,
                sharedText: sharedText,
                metadataTitle: metadata.title,
                metadataDescription: metadata.description,
                ocrLines: []
            )
        )
        if !textOnlyAnalysis.placesFound.isEmpty {
            let candidates = textOnlyAnalysis.placesFound.map {
                pendingReviewCandidate(from: $0, sourceURLString: sourceURLString, sourceText: evidenceText, ocrLines: [])
            }
            return rankedSocialAnalysisCandidates(candidates.map(markAsSocialAnalysisCandidate))
        }

        let ocrLines: [String]
        if let imageURL = metadata.imageURL,
           let imageData = await metadataImageData(from: imageURL) {
            ocrLines = await recognizedTextLines(from: imageData)
        } else {
            ocrLines = []
        }
        guard !ocrLines.isEmpty else {
            return textOnlyAnalysis.isPlaceBearing
                ? [placeBearingSourceReviewCandidate(from: textOnlyAnalysis, sourceURLString: sourceURLString, evidenceText: evidenceText)]
                : []
        }

        let ocrAnalysis = parser.analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: sourceURLString,
                resolvedURL: metadata.resolvedURL,
                sharedTitle: sharedTitle,
                sharedText: sharedText,
                metadataTitle: metadata.title,
                metadataDescription: metadata.description,
                ocrLines: ocrLines
            )
        )
        let candidates = ocrAnalysis.placesFound.map {
            pendingReviewCandidate(from: $0, sourceURLString: sourceURLString, sourceText: evidenceText, ocrLines: ocrLines)
        }
        if candidates.isEmpty, ocrAnalysis.isPlaceBearing {
            return [placeBearingSourceReviewCandidate(from: ocrAnalysis, sourceURLString: sourceURLString, evidenceText: evidenceText)]
        }
        return rankedSocialAnalysisCandidates(candidates.map(markAsSocialAnalysisCandidate))
    }

    private func placeBearingSourceReviewCandidate(
        from analysis: SocialPlaceAgentAnalysis,
        sourceURLString: String,
        evidenceText: String
    ) -> PendingReviewCandidate {
        let searchQueries = sourceRecoverySearchQueries(sourceURLString: sourceURLString, evidenceText: evidenceText, analysis: analysis)
        var found = ["Source URL: \(sourceURLString)", "Source intent: \(analysis.sourceIntent.rawValue)"]
        if let reason = analysis.placeBearingReason {
            found.append("Place-bearing source: \(reason)")
        }
        if let topic = analysis.topic {
            found.append("Topic clue: \(topic)")
        }
        found.append(contentsOf: analysis.regionClues.map { "Region clue: \($0)" })
        let diagnostic = SocialPlaceEvidenceDiagnostic(
            found: appendUniqueEvidence([], found),
            attempts: [
                "Checked public metadata/caption text for explicit place names",
                "Classified the source as place-bearing even though no exact venue was verified",
                "Kept this in Review instead of inventing a map pin",
                "Prepared public source-recovery search queries",
                "Did not use logged-in Instagram scraping"
            ],
            missingFields: appendUniqueEvidence([], [
                exactVenueMissingField(for: analysis.sourceIntent),
                "Verified address",
                "Verified coordinates"
            ]),
            nextBestClue: "Run source recovery search or add the exact place name/map link before saving as a Map Stamp.",
            suggestedSearchQueries: searchQueries.isEmpty ? nil : searchQueries
        )
        let candidateName = unresolvedPlaceCandidateName(from: searchQueries, analysis: analysis)
        let displayDiagnostic = candidateName.map {
            unresolvedPlaceDiagnostic(from: diagnostic, candidateName: $0)
        } ?? diagnostic
        return PendingReviewCandidate(
            candidateName: candidateName ?? placeBearingCandidateName(from: analysis),
            address: "",
            category: category(for: analysis.sourceIntent),
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: displayDiagnostic.found + displayDiagnostic.attempts + diagnosticSearchEvidence(displayDiagnostic) + ["Next best clue: \(displayDiagnostic.nextBestClue)"],
            confidence: confidence(for: analysis.sourceIntent),
            missingInfo: displayDiagnostic.missingFields,
            savedAt: Date(),
            evidenceDiagnostic: displayDiagnostic,
            reviewState: candidateName == nil ? "place_bearing_source" : "unresolved_place_candidate"
        )
    }

    private func sourceOnlyReviewCandidate(sourceURLString: String, evidenceText: String) -> PendingReviewCandidate {
        let searchQueries = sourceRecoverySearchQueries(sourceURLString: sourceURLString, evidenceText: evidenceText)
        let diagnostic = SocialPlaceEvidenceDiagnostic(
            found: ["Source URL: \(sourceURLString)"],
            attempts: [
                "Checked public metadata/caption text for explicit place names",
                "Checked social handles without treating creator handles as places",
                "Prepared public web search fallback queries for source-only recovery",
                "Did not use logged-in Instagram scraping"
            ],
            missingFields: ["Verified place name", "Verified address", "Verified coordinates"],
            nextBestClue: "Run the suggested public searches, or share a caption, screenshot/OCR frame, map link, or visible venue handle.",
            suggestedSearchQueries: searchQueries.isEmpty ? nil : searchQueries
        )
        if let candidateName = unresolvedPlaceCandidateName(from: searchQueries) {
            let upgradedDiagnostic = unresolvedPlaceDiagnostic(from: diagnostic, candidateName: candidateName)
            return PendingReviewCandidate(
                candidateName: candidateName,
                address: "",
                category: "attraction",
                sourceURL: sourceURLString,
                sourceText: evidenceText.isEmpty ? nil : evidenceText,
                evidence: upgradedDiagnostic.found + upgradedDiagnostic.attempts + diagnosticSearchEvidence(upgradedDiagnostic) + ["Next best clue: \(upgradedDiagnostic.nextBestClue)"],
                confidence: 0.32,
                missingInfo: upgradedDiagnostic.missingFields,
                savedAt: Date(),
                evidenceDiagnostic: upgradedDiagnostic,
                reviewState: "unresolved_place_candidate"
            )
        }
        return PendingReviewCandidate(
            candidateName: sourceOnlyDisplayName(for: sourceURLString),
            address: "",
            category: "attraction",
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: diagnostic.found + diagnostic.attempts + diagnosticSearchEvidence(diagnostic) + ["Next best clue: \(diagnostic.nextBestClue)"],
            confidence: 0,
            missingInfo: diagnostic.missingFields,
            savedAt: Date(),
            evidenceDiagnostic: diagnostic,
            isSourceOnly: true
        )
    }

    private func diagnosticSearchEvidence(_ diagnostic: SocialPlaceEvidenceDiagnostic) -> [String] {
        (diagnostic.suggestedSearchQueries ?? []).map { "Suggested public search: \($0)" }
    }

    private func sourceOnlyDisplayName(for sourceURLString: String) -> String {
        guard let url = URL(string: sourceURLString) else { return "Social link" }
        let path = url.path.lowercased()
        if path.contains("/reel/") || path.contains("/reels/") { return "Instagram reel" }
        if url.host?.lowercased().contains("instagram") == true { return "Instagram link" }
        return "Social link"
    }

    private func unresolvedPlaceDiagnostic(
        from diagnostic: SocialPlaceEvidenceDiagnostic,
        candidateName: String
    ) -> SocialPlaceEvidenceDiagnostic {
        var upgraded = diagnostic
        upgraded.found = appendUniqueEvidence(upgraded.found, ["Candidate place name: \(candidateName)"])
        upgraded.attempts = appendUniqueEvidence(upgraded.attempts, ["Promoted source clue to unresolved place candidate instead of showing the source as the title"])
        upgraded.missingFields = appendUniqueEvidence(
            upgraded.missingFields.filter { missing in
                let lowered = missing.lowercased()
                return !lowered.contains("place name") &&
                    !lowered.contains("exact restaurant name") &&
                    !lowered.contains("exact venue")
            },
            ["Verified address", "Verified coordinates"]
        )
        upgraded.nextBestClue = "Confirm the address or Google Places match before saving this as a Map Stamp."
        return upgraded
    }

    private func unresolvedPlaceCandidateName(
        from searchQueries: [String],
        analysis: SocialPlaceAgentAnalysis? = nil
    ) -> String? {
        let analysisHints = analysis.map { current in
            ([current.topic].compactMap { $0 } + current.recoveryHints
                .filter { $0.label != "region" && $0.label != "category" }
                .map(\.queryFragment))
        } ?? []

        for rawValue in analysisHints + searchQueries {
            guard let candidate = unresolvedPlaceCandidateName(fromRawSearchText: rawValue) else { continue }
            return candidate
        }
        return nil
    }

    private func unresolvedPlaceCandidateName(fromRawSearchText rawValue: String) -> String? {
        var candidate = cleanHTMLText(rawValue)
            .replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"site:\S+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\bD[A-Za-z0-9_-]{6,}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\binstagram\s+reel\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:restaurant|venue|place|address|cafe|coffee|hotel|map)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'“”"))

        if candidate.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil {
            for marker in [" 台北", " 臺北", " Taipei", " Taiwan", " 士林站", " Shilin Station"] {
                if let range = candidate.range(of: marker, options: [.caseInsensitive]) {
                    candidate = String(candidate[..<range.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        candidate = candidate
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，\"'“”"))

        guard candidate.count >= 2, candidate.count <= 80 else { return nil }
        let hasCJK = candidate.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil
        if !hasCJK && candidate.count <= 3 { return nil }
        guard isUsablePlaceName(candidate) else { return nil }
        guard !looksLikeMarketingLine(candidate) else { return nil }

        let lowered = candidate.lowercased()
        if ["la", "oc", "nyc", "sf", "taipei", "tokyo"].contains(lowered) { return nil }
        if ["士林", "西門", "大安", "信義", "萬華", "中山", "松山", "內湖", "板橋", "新莊", "蘆洲", "台北", "臺北"].contains(candidate) {
            return nil
        }
        let genericValues = [
            "instagram",
            "social link",
            "restaurant recommendation",
            "restaurants in",
            "restaurant in",
            "coffee shops in",
            "coffee shop in",
            "cafes in",
            "cafe in",
            "where to eat",
            "favorite restaurants",
            "best restaurants",
            "top restaurants",
            "hidden gems",
            "coffee shop clue",
            "place clue",
            "source clue"
        ]
        if genericValues.contains(where: { lowered.contains($0) }) { return nil }
        if lowered.range(of: #"^(favorite|favourite|best|top|must-try|must try|iconic)\b"#, options: .regularExpression) != nil {
            return nil
        }
        return candidate
    }

    private func sourceRecoverySearchQueries(
        sourceURLString: String,
        evidenceText: String,
        analysis: SocialPlaceAgentAnalysis? = nil
    ) -> [String] {
        var queries: [String] = []
        let url = URL(string: sourceURLString)
        let host = url?.host?.lowercased() ?? ""
        let cleanedEvidence = cleanHTMLText(evidenceText)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let analysis, analysis.isPlaceBearing {
            let keyword = searchKeyword(for: analysis.sourceIntent)
            let region = primaryRegion(from: analysis.regionClues)
            let phrase = meaningfulPlacePhrase(from: evidenceText)
            if let reelID = instagramReelID(in: url) {
                if let region {
                    queries.append("\"\(reelID)\" \(keyword) \(region)")
                }
                if let phrase {
                    queries.append("\"\(reelID)\" \"\(phrase)\"")
                }
                if let topic = analysis.topic {
                    queries.append("\"\(reelID)\" \"\(topic)\"")
                }
                queries.append("site:instagram.com/reel/\(reelID) \(keyword)")
            } else if let url, !host.isEmpty {
                queries.append("\(host) \(url.lastPathComponent) \(keyword)")
            }
            if let region, let phrase {
                queries.append("\"\(phrase)\" \(region) \(keyword)")
            }
            if let canonicalURL = canonicalSearchURL(from: url) {
                queries.append("\"\(canonicalURL)\"")
            }
            return Array(appendUniqueEvidence([], queries).prefix(4))
        }

        if let reelID = instagramReelID(in: url) {
            queries.append("instagram reel \(reelID) place")
            queries.append("\(reelID) restaurant venue")
        } else if let url, !host.isEmpty {
            queries.append("\(host) \(url.lastPathComponent) place")
        }

        if let handle = firstSocialHandle(in: evidenceText) {
            queries.append("@\(handle) address")
        }

        if !cleanedEvidence.isEmpty {
            queries.append("\"\(String(cleanedEvidence.prefix(80)))\" place")
        }

        if let canonicalURL = canonicalSearchURL(from: url) {
            queries.append("\"\(canonicalURL)\"")
        }

        return Array(appendUniqueEvidence([], queries).prefix(4))
    }

    private func placeBearingCandidateName(from analysis: SocialPlaceAgentAnalysis) -> String {
        let region = primaryRegion(from: analysis.regionClues)
        switch analysis.sourceIntent {
        case .restaurantRecommendation:
            return region.map { "\($0) restaurant recommendation clue" } ?? "Restaurant recommendation clue"
        case .cafeRecommendation:
            return region.map { "\($0) coffee shop clue" } ?? "Coffee shop clue"
        case .stayRecommendation:
            return region.map { "\($0) stay recommendation clue" } ?? "Stay recommendation clue"
        case .travelRecommendation:
            return region.map { "\($0) travel place clue" } ?? "Travel place clue"
        case .multiPlaceList:
            return analysis.topic ?? "Place list clue"
        case .singleVenuePost:
            return "Venue clue"
        case .unknownPlaceBearing:
            return region.map { "\($0) place clue" } ?? "Place clue"
        case .nonPlace, .creatorOnly:
            return "Social link"
        }
    }

    private func category(for intent: SocialPlaceSourceIntent) -> String {
        switch intent {
        case .restaurantRecommendation:
            return "food"
        case .cafeRecommendation:
            return "cafe"
        case .stayRecommendation:
            return "stay"
        case .travelRecommendation, .multiPlaceList, .singleVenuePost, .unknownPlaceBearing, .nonPlace, .creatorOnly:
            return "attraction"
        }
    }

    private func confidence(for intent: SocialPlaceSourceIntent) -> Double {
        switch intent {
        case .restaurantRecommendation, .cafeRecommendation, .stayRecommendation, .travelRecommendation:
            return 0.35
        case .multiPlaceList, .singleVenuePost:
            return 0.4
        case .unknownPlaceBearing:
            return 0.25
        case .nonPlace, .creatorOnly:
            return 0
        }
    }

    private func exactVenueMissingField(for intent: SocialPlaceSourceIntent) -> String {
        switch intent {
        case .restaurantRecommendation:
            return "Exact restaurant name"
        case .cafeRecommendation:
            return "Exact cafe name"
        case .stayRecommendation:
            return "Exact hotel/stay name"
        default:
            return "Exact place name"
        }
    }

    private func searchKeyword(for intent: SocialPlaceSourceIntent) -> String {
        switch intent {
        case .restaurantRecommendation:
            return "restaurant"
        case .cafeRecommendation:
            return "cafe"
        case .stayRecommendation:
            return "hotel resort"
        case .travelRecommendation, .multiPlaceList, .singleVenuePost, .unknownPlaceBearing, .nonPlace, .creatorOnly:
            return "place"
        }
    }

    private func primaryRegion(from regionClues: [String]) -> String? {
        guard let clue = regionClues.first else { return nil }
        let lowered = clue.lowercased()
        if lowered == "losangeles" || lowered == "la" || lowered == "lacoffee" { return "LA" }
        if lowered == "orangecounty" || lowered == "oc" || lowered == "ocfood" { return "Orange County" }
        if lowered == "newyork" { return "New York" }
        return clue
    }

    private func meaningfulPlacePhrase(from evidenceText: String) -> String? {
        let patterns = [
            #"(?i)\b((?:favorite|favourite|best|top|must-try|must try|iconic|hidden gems?|where to eat)[^.\n\r]{0,90})"#,
            #"(?i)\b((?:restaurants?|cafes?|coffee shops?|hotels?|resorts?|things to do|places to visit)\s+in\s+(?:LA|Los Angeles|OC|Orange County|Tokyo|Taipei|Seoul|Paris|London|New York|[A-Z][A-Za-z .'-]{2,60}))\b"#,
            #"((?:士林|西門|大安|信義|萬華|中山|松山|內湖|板橋|新莊|蘆洲)[^\n\r]{0,60}(?:壽喜燒|寿喜烧|漢堡排|日本料理|日式料理|餐廳|餐厅|美食))"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(evidenceText.startIndex..<evidenceText.endIndex, in: evidenceText)
            guard let match = regex.firstMatch(in: evidenceText, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: evidenceText) else { continue }
            let cleaned = cleanHTMLText(String(evidenceText[captureRange]))
                .replacingOccurrences(of: #"[📍👣🗺]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，\"'“”"))
            if cleaned.count >= 8, cleaned.count <= 120 {
                return cleaned
            }
        }
        return nil
    }

    private func instagramReelID(in url: URL?) -> String? {
        guard let url,
              url.host?.lowercased().contains("instagram") == true else { return nil }
        let components = url.pathComponents
        guard let markerIndex = components.firstIndex(where: { $0.lowercased() == "reel" || $0.lowercased() == "reels" }),
              components.indices.contains(markerIndex + 1) else { return nil }
        let id = components[markerIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return id.isEmpty ? nil : id
    }

    private func canonicalSearchURL(from url: URL?) -> String? {
        guard let url else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let value = components?.url?.absoluteString ?? url.absoluteString
        return value.isEmpty ? nil : value
    }

    private func pendingReviewCandidate(
        from draft: SocialPlaceCandidateDraft,
        sourceURLString: String,
        sourceText: String,
        ocrLines: [String]
    ) -> PendingReviewCandidate {
        let combinedSourceText = [sourceText, ocrLines.joined(separator: "\n")]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return PendingReviewCandidate(
            candidateName: draft.displayName,
            address: draft.locationClues.first ?? "",
            category: draft.category,
            sourceURL: sourceURLString,
            sourceText: combinedSourceText.isEmpty ? nil : combinedSourceText,
            evidence: evidenceStrings(from: draft, sourceURLString: sourceURLString),
            confidence: draft.confidence,
            missingInfo: draft.missingInfo,
            savedAt: Date()
        )
    }

    private func evidenceStrings(from draft: SocialPlaceCandidateDraft, sourceURLString: String) -> [String] {
        var values = sourceURLString.isEmpty ? [] : ["Source URL: \(sourceURLString)"]
        values.append(contentsOf: draft.evidenceChips)
        values.append(contentsOf: draft.evidence.compactMap { atom in
            atom.line.contains("Resolved public profile") ? atom.line : nil
        })
        if !draft.locationClues.isEmpty {
            values.append(contentsOf: draft.locationClues.map { "Location clue: \($0)" })
        }
        if !draft.venueHandles.isEmpty {
            values.append(contentsOf: draft.venueHandles.map { "Venue handle: @\($0)" })
        }
        if !draft.creatorHandles.isEmpty {
            values.append(contentsOf: draft.creatorHandles.map { "Creator handle: @\($0)" })
        }
        if !draft.bookingLinks.isEmpty {
            values.append(contentsOf: draft.bookingLinks.map { "Booking link: \($0)" })
        }
        return appendUniqueEvidence([], values)
    }

    private func rankedSocialAnalysisCandidates(_ candidates: [PendingReviewCandidate]) -> [PendingReviewCandidate] {
        var seenKeys = Set<String>()
        return candidates
            .sorted { lhs, rhs in
                socialAnalysisScore(lhs) > socialAnalysisScore(rhs)
            }
            .filter { candidate in
                let key = "\(SocialPlaceParser.canonicalPlaceName(candidate.candidateName))|\(SocialPlaceParser.canonicalPlaceName(candidate.address))"
                guard !seenKeys.contains(key) else { return false }
                seenKeys.insert(key)
                return true
            }
    }

    private func socialAnalysisScore(_ candidate: PendingReviewCandidate) -> Double {
        var score = candidate.confidence
        let evidence = candidate.evidence.joined(separator: " ").lowercased()
        if !candidate.address.isEmpty { score += 0.18 }
        if evidence.contains("ocr-derived candidate") { score += 0.08 }
        if evidence.contains("named place") || evidence.contains("named venue") || evidence.contains("place line") || evidence.contains("venue name") { score += 0.16 }
        if evidence.contains("venue handle") { score += 0.08 }
        if evidence.contains("resolved public profile") { score += 0.12 }
        if evidence.contains("instagram handle") || evidence.contains("social handle") { score += 0.04 }
        if SocialPlaceEvidenceScorer.isRejectedTitle(candidate.candidateName) { score -= 1.0 }
        return score
    }

    private func markAsSocialAnalysisCandidate(_ candidate: PendingReviewCandidate) -> PendingReviewCandidate {
        var analyzed = candidate
        analyzed.evidence = appendUniqueEvidence(
            analyzed.evidence,
            ["Analysis pipeline: collected metadata/caption/OCR anchors, scored candidate evidence, and kept unresolved fields for review"]
        )
        return analyzed
    }

    private func appendUniqueEvidence(_ values: [String], _ newValues: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values + newValues {
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func socialReviewCandidates(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> [PendingReviewCandidate] {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        let lines = evidenceText
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }

        var sections: [(name: String, details: [String])] = []
        var currentName: String?
        var currentDetails: [String] = []

        for line in lines {
            if let name = numberedCandidateName(from: line) {
                if let currentName {
                    sections.append((currentName, currentDetails))
                }
                currentName = name
                currentDetails = []
            } else if currentName != nil {
                currentDetails.append(line)
            }
        }
        if let currentName {
            sections.append((currentName, currentDetails))
        }

        let candidates: [PendingReviewCandidate] = sections.compactMap { section in
            let name = cleanPlaceName(section.name)
            guard isUsablePlaceName(name) else { return nil }
            let detailsText = section.details.joined(separator: "\n")
            let address = firstLocationPin(in: detailsText) ?? streetAddressLine(in: detailsText) ?? locatedCity(in: detailsText) ?? cityAddress(in: detailsText) ?? ""
            let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
            var evidence = [
                "Source URL: \(sourceURLString)",
                "Evidence tier: \(tier.rawValue)",
                "Public metadata candidate: \(name)"
            ]
            if !address.isEmpty {
                evidence.append("Location clue: \(address)")
            }
            if !detailsText.isEmpty {
                evidence.append(String(detailsText.prefix(300)))
            }

            return PendingReviewCandidate(
                candidateName: name,
                address: address,
                category: fallbackCategory(from: "\(name) \(detailsText)"),
                sourceURL: sourceURLString,
                sourceText: evidenceText.isEmpty ? nil : evidenceText,
                evidence: evidence,
                confidence: address.isEmpty ? 0.48 : 0.58,
                missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
                savedAt: Date()
            )
        }

        var seenKeys = Set<String>()
        return candidates.filter { candidate in
            let key = "\(candidate.candidateName.lowercased())|\(candidate.address.lowercased())"
            guard !seenKeys.contains(key) else { return false }
            seenKeys.insert(key)
            return true
        }
    }

    private func numberedCandidateName(from line: String) -> String? {
        firstRegexCapture(in: line, pattern: #"^\s*(?:\d{1,2}[\.)]|[①②③④⑤⑥⑦⑧⑨])\s*([^\n\r]+)"#)
    }

    private func bracketedPlaceName(in content: String) -> String? {
        let patterns = [
            #"[\[【]\s*([^\]】]{2,80})\s*[\]】]"#,
            #"(?i)\b(?:at|spot|place)\s+([A-Z][A-Za-z0-9 &'._-]{2,60})\s*(?:[-–—|,]|\n)"#
        ]
        for pattern in patterns {
            if let match = firstRegexCapture(in: content, pattern: pattern) {
                let cleaned = cleanPlaceName(match)
                if isUsablePlaceName(cleaned) {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func venueIntroName(in content: String) -> String? {
        let lines = content
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }

        for line in lines where looksLikeVenueIntroLine(line) {
            if let quoted = firstRegexCapture(in: line, pattern: #"[「『\"]\s*([^」』\"]{2,80})\s*[」』\"]"#) {
                let cleaned = cleanPlaceName(quoted)
                if isUsablePlaceName(cleaned), !looksLikeMarketingLine(cleaned) {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func looksLikeVenueIntroLine(_ line: String) -> Bool {
        let pattern = #"名店|餐廳|餐厅|正式插旗|插旗|開幕|新店|店名|restaurant|from\s+tokyo|來自東京|頂級燒肉"#
        return line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func chineseVenueName(in content: String) -> String? {
        let patterns = [
            #"(?:^|[\n\r])[-\s]*(?:[\u4e00-\u9fff]{0,4})?(?:全新開幕|新開幕|開幕)\s*([^\s新主题主題\-－—–:]{2,16})\s*(?:新主題|主题|主題)\s*[-－—–:]\s*([\u4e00-\u9fffA-Za-z0-9]{2,24})"#,
            #"([\u4e00-\u9fffA-Za-z0-9]{2,24})\s*[·・‧]\s*([\u4e00-\u9fffA-Za-z0-9]{2,24})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            guard let match = regex.firstMatch(in: content, range: range), match.numberOfRanges > 2,
                  let brandRange = Range(match.range(at: 1), in: content),
                  let themeRange = Range(match.range(at: 2), in: content) else { continue }
            let brand = cleanPlaceName(String(content[brandRange]))
            let theme = cleanPlaceName(String(content[themeRange]))
            let name = "\(brand)·\(theme)"
            if isUsablePlaceName(name), !looksLikeMarketingLine(name) {
                return name
            }
        }
        return nil
    }

    private func firstLocationPin(in content: String) -> String? {
        let patterns = [
            #"📍\s*([^\n\r\.]+)"#,
            #"\bLocation:\s*([^\n\r\.]+)"#
        ]
        for pattern in patterns {
            if let match = firstRegexCapture(in: content, pattern: pattern) {
                let cleaned = cleanHTMLText(match)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    private func inferredPlaceLineBeforeAddress(in content: String) -> (name: String, address: String)? {
        let lines = content
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return nil }

        for (index, line) in lines.enumerated() where looksLikeAddressLine(line) {
            let priorLines = Array(lines.prefix(index))

            // Prefer structural venue anchors over the closest freeform line.
            // This mirrors the manual analysis flow: first look for an explicit
            // venue token (`Venue / menu`, quoted venue, or handle), then use the
            // address as corroborating evidence. It avoids treating review-section
            // headers, dishes, or prose near the address as place names.
            for priorLine in priorLines {
                guard let candidate = candidateNameFromCaptionLine(priorLine) else { continue }
                if isLikelyCaptionPlaceName(candidate) {
                    return (candidate, line)
                }
            }

            var previousIndex = index - 1
            while previousIndex >= 0 {
                let candidate = cleanPlaceName(lines[previousIndex])
                if isLikelyCaptionPlaceName(candidate) {
                    return (candidate, line)
                }
                previousIndex -= 1
            }
        }
        return nil
    }

    private func streetAddressLine(in content: String) -> String? {
        let lines = content
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }
        return lines.first(where: looksLikeAddressLine)
    }

    private func looksLikeAddressLine(_ line: String) -> Bool {
        SocialPlaceEvidenceScorer.looksLikeAddressLine(line)
    }

    private func isLikelyCaptionPlaceName(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(value)
    }

    private func candidateNameFromCaptionLine(_ line: String) -> String? {
        if !looksLikeAddressLine(line),
           line.contains("@"),
           let pinnedName = firstRegexCapture(in: line, pattern: #"📍\s*([^@\n\r]{2,80})(?:\s+@[A-Za-z0-9._]{3,30})?"#) {
            let cleaned = cleanPlaceName(pinnedName)
            if isUsablePlaceName(cleaned),
               !looksLikeAddressLine(cleaned),
               !looksLikeOperatingHoursLine(cleaned),
               !looksLikeReviewMetricLine(cleaned),
               !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }

        if let leadingName = firstRegexCapture(in: line, pattern: #"^([^/\n]{2,60})\s*/"#) {
            let cleaned = cleanPlaceName(leadingName)
            if isUsablePlaceName(cleaned),
               !looksLikeAddressLine(cleaned),
               !looksLikeOperatingHoursLine(cleaned),
               !looksLikeReviewMetricLine(cleaned),
               !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }

        let isVenueIntroLine = line.range(of: #"@|名店|插旗|開幕|新店|店名|餐廳|餐厅|restaurant"#, options: [.regularExpression, .caseInsensitive]) != nil
        if isVenueIntroLine,
           let quoted = firstRegexCapture(in: line, pattern: #"[「\"]\s*([^」\"]{2,60})\s*[」\"]"#) {
            let cleaned = cleanPlaceName(quoted)
            if isUsablePlaceName(cleaned), !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }
        if let handle = firstRegexCapture(in: line, pattern: #"@([A-Za-z0-9._]{3,30})"#) {
            let cleaned = SocialPlaceEvidenceScorer.resolvedDisplayName(fromSocialHandle: handle).name
            if isUsablePlaceName(cleaned), !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }
        return nil
    }

    private func looksLikeOperatingHoursLine(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.looksLikeOperatingHoursLine(value)
    }

    private func looksLikeReviewMetricLine(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.looksLikeReviewMetricLine(value)
    }

    private func looksLikeMarketingLine(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.looksLikeMarketingLine(value)
    }

    private func cityAddress(in content: String) -> String? {
        firstRegexCapture(in: content, pattern: #"\b([A-Z][A-Za-z .'-]{2,40},\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA|HI|UT|CO|Bali|Indonesia|Chongqing|China))\b"#)
            .map(cleanHTMLText)
    }

    private func locatedCity(in content: String) -> String? {
        firstRegexCapture(in: content, pattern: #"(?i)\b(?:located|based)\s+in\s+([A-Z][A-Za-z .'-]{2,40})(?:[.!?,\n\r]|$)"#)
            .map(cleanHTMLText)
    }

    private func publicMetadataEvidence(from metadata: ShareMetadata, sharedTitle: String, sharedText: String) -> String {
        [sharedTitle, sharedText, metadata.title, metadata.description]
            .compactMap { $0 }
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func firstPlaceName(in content: String) -> String? {
        let patterns = [
            #"[\[【]\s*([^\]】]{2,80})\s*[\]】]"#
        ]

        for pattern in patterns {
            if let match = firstRegexCapture(in: content, pattern: pattern) {
                let cleaned = cleanPlaceName(match)
                if isUsablePlaceName(cleaned) {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func firstAddress(in content: String) -> String? {
        let patterns = [
            #"\b\d{1,6}\s+[A-Za-z0-9][A-Za-z0-9 .,'#&/-]+,\s*[A-Za-z .'-]+,\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?\b"#,
            #"\b\d{1,6}\s+[A-Za-z0-9][A-Za-z0-9 .,'#&/-]+,\s*[A-Za-z .'-]+,\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA)\b"#
        ]

        for pattern in patterns {
            if let match = firstRegexMatch(in: content, pattern: pattern) {
                return cleanHTMLText(match)
            }
        }
        return nil
    }

    private func firstSocialHandle(in content: String) -> String? {
        let ignoredHandles: Set<String> = [
            "instagram", "reels", "reel", "explore", "threads", "tiktok", "xiaohongshu", "save"
        ]
        guard let regex = try? NSRegularExpression(pattern: #"@([A-Za-z0-9._]{3,30})"#) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, range: range)

        for match in matches {
            guard match.numberOfRanges > 1,
                  let handleRange = Range(match.range(at: 1), in: content) else { continue }
            let handle = String(content[handleRange]).lowercased()
            guard !ignoredHandles.contains(handle),
                  !handle.contains("instagram"),
                  handle.range(of: #"\d{5,}"#, options: .regularExpression) == nil else {
                continue
            }
            return handle
        }
        return nil
    }

    private func displayName(fromSocialHandle handle: String) -> String {
        SocialPlaceEvidenceScorer.displayName(fromSocialHandle: handle)
    }

    private func firstRegexCapture(in content: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[captureRange])
    }

    private func firstRegexMatch(in content: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              let matchRange = Range(match.range, in: content) else {
            return nil
        }
        return String(content[matchRange])
    }

    private func cleanPlaceName(_ value: String) -> String {
        SocialPlaceEvidenceScorer.cleanCandidateName(value)
            .replacingOccurrences(of: #"\s*\(@[A-Za-z0-9._]{3,30}\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+@[A-Za-z0-9._]{3,30}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!。！"))
    }

    private func isUsablePlaceName(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.isUsableCandidateName(value)
    }

    private func dishHints(from content: String) -> [String] {
        let keywords = ["matcha", "hojicha", "latte", "coffee", "tea", "ramen", "noodle", "pizza", "taco", "burger", "sushi", "dessert"]
        let lowercased = content.lowercased()
        return keywords.filter { lowercased.contains($0) }.prefix(4).map { keyword in
            keyword.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
        }
    }

    private func priceRangeHint(from content: String) -> String? {
        if content.range(of: #"\$\d+"#, options: .regularExpression) != nil {
            return "$$"
        }
        return nil
    }

    private func hasMeaningfulPlaceContext(_ content: String, sourceURLString: String) -> Bool {
        guard let url = URL(string: sourceURLString),
              isSocialURL(url) else {
            return true
        }

        let withoutURLs = content
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b[a-z0-9.-]+\.(com|net|cn|link)\S*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let hasCityOrAddress = withoutURLs.range(of: #"(北京|上海|广州|深圳|成都|杭州|Tokyo|Beijing|Shanghai|Los Angeles|New York|San Francisco|\d{1,5}\s+\S+)"#, options: [.regularExpression, .caseInsensitive]) != nil
        let hasEnoughText = withoutURLs.count >= 8
        return hasCityOrAddress || hasEnoughText
    }

    private func validateAIPlace(_ place: ParsedPlace, against content: String, sourceURLString: String) throws {
        let combinedPlace = "\(place.name) \(place.address)".lowercased()
        let source = content.lowercased()
        let conflicts = [
            ("北京", "beijing", "上海", "shanghai"),
            ("上海", "shanghai", "北京", "beijing")
        ]

        for (sourceChinese, sourceEnglish, wrongChinese, wrongEnglish) in conflicts {
            let sourceMentionsCity = source.contains(sourceChinese) || source.contains(sourceEnglish)
            let placeMentionsWrongCity = combinedPlace.contains(wrongChinese) || combinedPlace.contains(wrongEnglish)
            if sourceMentionsCity && placeMentionsWrongCity {
                throw NSError(domain: "save", code: 7, userInfo: [NSLocalizedDescriptionKey: "The parsed place conflicts with the city in the post. Share the exact map link to avoid saving the wrong place."])
            }
        }

        if let url = URL(string: sourceURLString), isSocialURL(url), place.name == "Unknown Place" {
            throw NSError(domain: "save", code: 8, userInfo: [NSLocalizedDescriptionKey: "SAV-E could not identify one exact place from this social post."])
        }
    }

    private func hasReliableCoordinates(_ place: ParsedPlace) -> Bool {
        guard let latitude = place.latitude,
              let longitude = place.longitude else {
            return false
        }
        return isValidCoordinate(latitude: latitude, longitude: longitude)
    }

    private func reviewCandidate(from place: ParsedPlace, sourceURLString: String, sourceText: String) -> PendingReviewCandidate? {
        let name = cleanPlaceName(place.name)
        guard isUsablePlaceName(name), name != "Unknown Place" else { return nil }

        let hasAddress = !place.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: hasAddress)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "AI extracted review candidate: \(name)",
            "No reliable coordinates in source; kept out of Map Stamp"
        ]
        if hasAddress {
            evidence.append("Location clue: \(place.address)")
        }
        if !sourceText.isEmpty {
            evidence.append(String(sourceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: place.address,
            category: place.category,
            sourceURL: sourceURLString,
            sourceText: sourceText.isEmpty ? nil : sourceText,
            evidence: evidence,
            confidence: hasAddress ? 0.62 : 0.52,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(
                tier: tier,
                hasAddress: hasAddress,
                source: "Gemini extracted a likely place but did not provide verified coordinates"
            ),
            savedAt: Date()
        )
    }

    private func isSocialURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "xhslink.com" ||
            host.hasSuffix("xiaohongshu.com") ||
            host.hasSuffix("instagram.com") ||
            host.hasSuffix("threads.net") ||
            host.hasSuffix("threads.com") ||
            host.hasSuffix("tiktok.com") ||
            host.hasSuffix("douyin.com")
    }

    private func deterministicMapPlace(from content: String, title: String, text: String) -> ParsedPlace? {
        guard let url = URL(string: content),
              isMapURL(url),
              let coordinates = mapCoordinates(from: url) else {
            return nil
        }

        let name = bestMapName(from: url, title: title, text: text)
        guard !name.isEmpty else { return nil }

        let address = mapAddress(from: url, text: text)
        let category = fallbackCategory(from: [name, address, text].joined(separator: " "))

        return ParsedPlace(
            name: name,
            address: address,
            category: category,
            iconName: iconForCategory(category),
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            dishes: [],
            priceRange: nil
        )
    }

    private func isMapURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "maps.apple.com" { return true }
        if host == "maps.app.goo.gl" || host == "goo.gl" || host == "g.co" { return true }
        if host == "maps.google.com" { return true }
        return (host == "google.com" || host.hasSuffix(".google.com")) && url.path.lowercased().hasPrefix("/maps")
    }

    private func mapCoordinates(from url: URL) -> (latitude: Double, longitude: Double)? {
        let full = [url.path, url.query ?? "", url.fragment ?? ""].joined(separator: "?")

        if let match = full.firstMatch(of: #/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/#),
           let lat = Double(match.1),
           let lng = Double(match.2),
           isValidCoordinate(latitude: lat, longitude: lng) {
            return (lat, lng)
        }

        if let match = full.firstMatch(of: #/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/#),
           let lat = Double(match.1),
           let lng = Double(match.2),
           isValidCoordinate(latitude: lat, longitude: lng) {
            return (lat, lng)
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for key in ["ll", "sll", "center"] {
            if let value = components?.queryItems?.first(where: { $0.name == key })?.value,
               let coordinate = coordinatePair(from: value) {
                return coordinate
            }
        }

        if let q = components?.queryItems?.first(where: { $0.name == "q" })?.value,
           let coordinate = coordinatePair(from: q) {
            return coordinate
        }

        return nil
    }

    private func coordinatePair(from value: String) -> (latitude: Double, longitude: Double)? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: ",", maxSplits: 1).map { String($0) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lng = Double(parts[1]),
              isValidCoordinate(latitude: lat, longitude: lng) else {
            return nil
        }
        return (lat, lng)
    }

    private func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180 && !(latitude == 0 && longitude == 0)
    }

    private func bestMapName(from url: URL, title: String, text: String) -> String {
        for candidate in [cleanFallbackName(title), queryName(from: url.absoluteString), cleanFallbackName(text)] {
            let cleaned = cleanFallbackName(candidate)
            if !cleaned.isEmpty,
               !cleaned.hasPrefix("http://"),
               !cleaned.hasPrefix("https://"),
               !cleaned.contains("@") {
                return cleaned
            }
        }
        return ""
    }

    private func mapAddress(from url: URL, text: String) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for key in ["address", "daddr", "destination"] {
            if let value = components?.queryItems?.first(where: { $0.name == key })?.value,
               coordinatePair(from: value) == nil,
               !value.isEmpty {
                return value
            }
        }
        return fallbackAddress(from: text)
    }

    private func queryName(from content: String) -> String {
        guard let url = URL(string: content),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return ""
        }

        for key in ["q", "query", "search", "destination", "daddr"] {
            if let value = components.queryItems?.first(where: { $0.name == key })?.value, !value.isEmpty {
                return value
            }
        }

        let decodedPath = url.path.removingPercentEncoding ?? url.path
        for prefix in ["/maps/place/", "/maps/search/"] {
            if decodedPath.hasPrefix(prefix) {
                let value = decodedPath
                    .dropFirst(prefix.count)
                    .split(separator: "/")
                    .first
                    .map(String.init) ?? ""
                return value.replacingOccurrences(of: "+", with: " ")
            }
        }

        return decodedPath
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func cleanFallbackName(_ value: String) -> String {
        value
            .replacingOccurrences(of: " - Google Maps", with: "")
            .replacingOccurrences(of: "| Google Maps", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fallbackAddress(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.first(where: { line in
            line.range(of: #"\d+ .+"#, options: .regularExpression) != nil
        }) ?? ""
    }

    private func fallbackCategory(from content: String) -> String {
        let value = content.lowercased()
        let stayCategoryPattern = #"\b(inn|guest ?house|ryokan|motel)\b|酒店|飯店|饭店|旅館|旅馆|旅店|旅宿|民宿|客棧|客栈|度假村|ホテル|ゲストハウス|료칸|호텔|리조트|모텔|여관|여인숙|게스트하우스"#
        if value.contains("cafe") || value.contains("coffee") || value.contains("tea") { return "cafe" }
        if value.contains("bar") || value.contains("cocktail") { return "bar" }
        if value.contains("hotel") || value.contains("stay") || value.contains("resort") || content.range(of: stayCategoryPattern, options: [.regularExpression, .caseInsensitive]) != nil { return "stay" }
        if value.contains("shop") || value.contains("store") { return "shopping" }
        if value.contains("bakery") || value.contains("restaurant") || value.contains("food") || value.contains("dessert") || value.contains("cake") { return "food" }
        if content.range(of: #"晚餐|餐廳|餐厅|美食|咖啡|茶|酒吧|料理|餐|燒肉|烧肉|火鍋|火锅|牛舌|巴斯克|蛋糕|甜點|甜点"#, options: .regularExpression) != nil { return "food" }
        return "attraction"
    }

    private func userFacingParseError(from error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == 429 {
            return "AI is busy right now. Try again in a minute."
        }
        if nsError.code == 401 || nsError.code == 403 {
            return "AI access needs attention."
        }
        return error.localizedDescription
    }

    private func geminiAPIKey() -> String? {
        SAVEProductionConfig.configValue(for: ["GEMINI_API_KEY"])
    }

    // MARK: - Save

    private func savePlace() {
        guard let place = parsedPlace else { return }
        guard let latitude = place.latitude,
              let longitude = place.longitude,
              isValidCoordinate(latitude: latitude, longitude: longitude) else {
            if let candidate = reviewCandidate(
                from: place,
                sourceURLString: sharedURL.isEmpty ? sharedText : sharedURL,
                sourceText: sharedText
            ) {
                reviewCandidate = candidate
                parsedPlace = nil
                return
            }
            parseError = "SAV-E needs reliable coordinates before saving a Map Stamp."
            return
        }

        let pendingPlace = PendingSharedPlace(
            name: place.name,
            address: place.address,
            category: selectedCategory,
            latitude: latitude,
            longitude: longitude,
            dishes: place.dishes,
            priceRange: place.priceRange,
            sourceURL: sharedURL.isEmpty ? nil : sharedURL,
            sourceText: sharedText.isEmpty ? nil : sharedText,
            savedAt: Date()
        )

        guard let fileURL = appGroupFileURL(named: SAVEProductionConfig.pendingPlacesFileName) else {
            parseError = "Shared app storage is unavailable"
            return
        }
        guard appendPendingItems([pendingPlace], to: fileURL, as: PendingSharedPlace.self) else { return }

        savedReviewCandidateCount = nil
        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func saveReviewCandidates() {
        let candidates = reviewCandidates.isEmpty ? reviewCandidate.map { [$0] } ?? [] : reviewCandidates
        saveReviewCandidates(candidates)
    }

    private func saveReviewCandidates(_ candidates: [PendingReviewCandidate]) {
        guard !candidates.isEmpty else { return }
        guard let fileURL = appGroupFileURL(named: SAVEProductionConfig.pendingReviewCandidatesFileName) else {
            parseError = "Shared app storage is unavailable"
            return
        }

        guard appendPendingItems(candidates, to: fileURL, as: PendingReviewCandidate.self) else { return }

        savedReviewCandidateCount = candidates.count
        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func saveSourceOnlyMemory(_ source: String, reason: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SAVEProductionConfig.appGroupSuiteName) else {
            return
        }

        let fileURL = containerURL.appendingPathComponent("save-memory-records.json")
        var records = loadMemoryRecords(from: fileURL)
        let searchQueries = sourceRecoverySearchQueries(sourceURLString: source, evidenceText: sharedText)
        let diagnostic = SocialPlaceEvidenceDiagnostic(
            found: ["Source URL: \(source)"],
            attempts: [reason, "Kept this as a source-only clue instead of inventing a place", "Prepared public web search fallback queries for source-only recovery"].filter { !$0.isEmpty },
            missingFields: ["Verified place name", "Verified address", "Verified coordinates"],
            nextBestClue: "Run the suggested public searches, or share a caption, screenshot/OCR frame, map link, or visible venue handle.",
            suggestedSearchQueries: searchQueries.isEmpty ? nil : searchQueries
        )
        let record = ShareMemoryRecord(
            id: UUID(),
            state: "source_only",
            sourceURL: URL(string: source)?.absoluteString ?? (sharedURL.isEmpty ? nil : sharedURL),
            sourceText: sharedText.isEmpty ? reason : sharedText,
            title: sharedTitle.isEmpty ? (URL(string: source)?.host() ?? "Shared source") : sharedTitle,
            placeName: nil,
            address: nil,
            evidence: diagnostic.found + diagnostic.attempts + diagnosticSearchEvidence(diagnostic),
            evidenceDiagnostic: diagnostic,
            createdAt: Date()
        )
        records.insert(record, at: 0)

        guard let data = try? JSONEncoder.shareMemory.encode(records) else { return }
        _ = write(data, to: fileURL)
    }

    private func loadMemoryRecords(from fileURL: URL) -> [ShareMemoryRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.shareMemory.decode([ShareMemoryRecord].self, from: data)) ?? []
    }

    private func appGroupFileURL(named fileName: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SAVEProductionConfig.appGroupSuiteName)?
            .appendingPathComponent(fileName)
    }

    private func appendPendingItems<Element: Codable>(_ items: [Element], to fileURL: URL, as elementType: Element.Type) -> Bool {
        guard !items.isEmpty else { return true }

        var success = false
        let coordinated = coordinate(fileURL, purpose: "append pending queue") {
            do {
                let existing = try loadArray([Element].self, from: fileURL)
                let data = try JSONEncoder().encode(existing + items)
                success = write(data, to: fileURL)
            } catch {
                parseError = "Couldn't read shared app storage"
                success = false
            }
        }
        return coordinated && success
    }

    private func loadArray<Element: Decodable>(_ type: [Element].Type, from fileURL: URL) throws -> [Element] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(type, from: data)
    }

    private func coordinate(_ fileURL: URL, purpose: String, _ work: () -> Void) -> Bool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: fileURL, options: [], error: &coordinationError) { _ in
            work()
        }
        if coordinationError != nil {
            parseError = "Couldn't coordinate shared app storage"
            return false
        }
        return true
    }

    private func write(_ data: Data, to fileURL: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            parseError = "Couldn't write shared app storage"
            return false
        }
    }

    // MARK: - Helpers

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "food": return "fork.knife"
        case "cafe": return "cup.and.saucer.fill"
        case "bar": return "wineglass.fill"
        case "attraction": return "star.fill"
        case "stay": return "bed.double.fill"
        case "shopping": return "bag.fill"
        default: return "mappin"
        }
    }
}

private extension JSONEncoder {
    static var shareMemory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var shareMemory: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Hex Color (standalone for extension target)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

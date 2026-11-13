#if SAVVY_CITY_MVP
import SwiftUI

/// Prototype presentation only. Existing review callbacks own every decision.
struct CityMVPReviewCandidateCard: View {
    let candidate: PlaceReviewCandidate
    let tripName: String?
    @Binding var displayName: String
    let primaryTitle: String
    let primarySymbol: String
    let canConfirm: Bool
    let isWorking: Bool
    let onPrimary: () -> Void
    let onSearch: () -> Void
    let onOpenMap: () -> Void
    let onReject: () -> Void
    let onKeepSource: () -> Void
    let onInvestigate: () -> Void
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CityMVPFormSteps(titles: [t("Clue", "線索"), t("Review", "確認"), t("Save", "收藏")], selected: 1)
            VStack(alignment: .leading, spacing: 10) {
                Label(t("Not saved", "尚未收藏"), systemImage: "questionmark.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(CityMVPFormStyle.muted)
                    .accessibilityIdentifier("drawer.review.notSaved")
                Text(candidate.name).font(.title2.bold()).textSelection(.enabled)
                    .accessibilityIdentifier("drawer.review.name")
                if !candidate.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(candidate.address).font(.subheadline).textSelection(.enabled)
                        .foregroundStyle(CityMVPFormStyle.muted)
                }
                if let tripName { Text(t("For \(tripName)", "準備加入「\(tripName)」")).font(.caption) }
                Text(canConfirm
                     ? t("Check the place and branch before saving.", "收藏前請確認地點與分店。")
                     : t("We still need an exact place. Your source alone does not create a map pin.", "還需要確認精確地點；只有來源不會產生地圖標記。"))
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("drawer.review.missingClue")
            }
            if canConfirm {
                Button(t("Open on the map", "在地圖上打開"), action: onOpenMap)
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .accessibilityIdentifier("drawer.review.heroMap")
            }
            VStack(spacing: 10) {
                Button(action: onPrimary) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(CityMVPFormStyle.canvas)
                        .background(CityMVPFormStyle.ink, in: Capsule())
                }.accessibilityIdentifier("drawer.review.primaryAction")
                HStack(spacing: 10) {
                    Button(action: onSearch) {
                        Text(canConfirm ? t("Choose another place", "改選其他地點") : t("Search for this place", "搜尋這個地點"))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.accessibilityIdentifier(canConfirm ? "drawer.review.changePlace" : "drawer.review.addClue")
                    Button(role: .destructive, action: onReject) {
                        Text(t("Not this place", "不是這間")).frame(maxWidth: .infinity, minHeight: 48)
                    }.accessibilityIdentifier("drawer.review.reject")
                }.font(.subheadline.weight(.semibold))
                    .background(CityMVPFormStyle.card, in: RoundedRectangle(cornerRadius: 22))
            }.accessibilityElement(children: .contain)
                .accessibilityIdentifier("drawer.review.firstViewport")
            DisclosureGroup(t("Source details", "來源詳情")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(t("These are source clues, not verified facts.", "這些是來源線索，並非已驗證事實。"))
                        .font(.caption).foregroundStyle(CityMVPFormStyle.muted)
                    ForEach(Array(candidate.evidence.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.subheadline).textSelection(.enabled)
                    }
                }.padding(.top, 12)
            }
            DisclosureGroup(t("More options", "更多選項")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(t("Display name", "顯示名稱"), text: $displayName)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("drawer.review.editName")
                    Button(t("Investigate source", "繼續調查來源"), action: onInvestigate)
                        .frame(minHeight: 44).accessibilityIdentifier("drawer.review.reanalyze")
                    Button(t("Keep source only", "只留來源"), action: onKeepSource)
                        .frame(minHeight: 44).accessibilityIdentifier("drawer.review.keepSource")
                }.padding(.top, 12)
            }.accessibilityIdentifier("drawer.review.belowFold")
        }
        .padding(20).background(CityMVPFormStyle.canvas, in: RoundedRectangle(cornerRadius: 28))
        .foregroundStyle(CityMVPFormStyle.ink).buttonStyle(.plain)
        .disabled(isWorking).opacity(isWorking ? 0.65 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.review.prototypeBody")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}
#endif

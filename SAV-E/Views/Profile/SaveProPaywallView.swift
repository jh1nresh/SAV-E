import StoreKit
import SwiftUI

/// Savvy Pro paywall — Doodle v1 full-screen modal (DESIGN 2026-10-20).
///
/// Presented only as a reaction to a refused AI assist, or pulled up
/// deliberately from Passport. Never automatic, never at launch, never before
/// the first confirmed Map Stamp — `SaveEntitlementStore.shouldPresentPaywall`
/// enforces that and this view does not second-guess it.
///
/// Pro v1 names one benefit: unlimited saved places. Quota headlines,
/// itinerary planning, and collectible extras stay off this screen.
/// Product IDs and purchase / restore logic are unchanged.
///
/// App Store review requirements that must stay on this screen: Restore
/// Purchases, EULA link, privacy policy link, renewal period, cancellation path.
struct SaveProPaywallView: View {
    enum Trigger: Equatable {
        /// The user asked for an AI assist and had none left.
        case aiAssistExhausted
        /// The user opened Pro from Passport.
        case passport
    }

    let trigger: Trigger

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings

    @State private var storeKit = SaveStoreKitService.shared
    @State private var selectedProductID: String = SAVEProAccessPolicy.ProductID.annual
    @State private var isPurchasing = false
    @State private var statusMessage: String?
    @State private var didFinishProductLoad = false

    var body: some View {
        ZStack {
            SaveAtlasPalette.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                stamp
                    .padding(.top, SaveSpace.xl)
                headline
                    .padding(.top, SaveSpace.md)
                benefitCard
                    .padding(.top, SaveSpace.md)
                savedNote
                    .padding(.top, SaveSpace.md)
                Spacer(minLength: SaveSpace.lg)
                    .overlay(alignment: .bottom) {
                        saleStateNotice
                            .padding(.bottom, SaveSpace.sm)
                    }
                offers
                legalFooter
                    .padding(.top, SaveSpace.sm)
            }
            .padding(.horizontal, SaveLayout.screenMargin)
            .padding(.bottom, SaveSpace.sm)
        }
        .presentationBackground(SaveAtlasPalette.canvas)
        .interactiveDismissDisabled(isPurchasing)
        .accessibilityIdentifier("paywall.root")
        .accessibilityValue(trigger == .passport ? "passport" : "aiAssist")
        .task {
            await storeKit.loadProducts()
            didFinishProductLoad = true
            if storeKit.products.contains(where: { $0.id == SAVEProAccessPolicy.ProductID.annual }) {
                selectedProductID = SAVEProAccessPolicy.ProductID.annual
            } else if storeKit.products.contains(where: { $0.id == SAVEProAccessPolicy.ProductID.monthly }) {
                selectedProductID = SAVEProAccessPolicy.ProductID.monthly
            }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                SaveHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .frame(width: SaveLayout.minTap, height: SaveLayout.minTap)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("paywall.close")
        }
        .frame(height: SaveLayout.minTap)
    }

    private var stamp: some View {
        SaveDoodlePaywallStamp()
            .frame(width: 120, height: 120)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var headline: some View {
        SaveDisplayTitle(
            text: "Savvy Pro",
            pointSize: 34,
            relativeTo: .largeTitle
        )
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("paywall.header")
    }

    private var benefitCard: some View {
        HStack(spacing: SaveLayout.stickerToText) {
            SaveDoodleForestCheck()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(languageSettings.localized(
                english: "Unlimited saved places",
                traditionalChinese: "收藏地點不設限"
            ))
            .font(SaveAtlasType.strong(17))
            .foregroundStyle(SaveAtlasPalette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SaveSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SaveLayout.rowMinHeight)
        .background(
            SaveAtlasPalette.paper,
            in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                .stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
        }
        .accessibilityIdentifier("paywall.benefit.unlimited")
    }

    private var savedNote: some View {
        Text(languageSettings.localized(
            english: "Keep saving the places you love.",
            traditionalChinese: "繼續收藏你喜歡的地方。"
        ))
        .font(SaveAtlasType.body(15))
        .foregroundStyle(SaveAtlasPalette.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("paywall.savedNote")
    }

    /// Sale-state copy sits in the spacer above the CTA so the 56pt coral
    /// button stays on the DESIGN y594 lock when purchasing is off.
    @ViewBuilder
    private var saleStateNotice: some View {
        if showsNotForSale || hasStatusNotice {
            VStack(spacing: SaveSpace.xs) {
                if showsNotForSale {
                    Text(notForSaleText)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("paywall.notForSale")
                }
                if let statusMessage, statusMessage != notForSaleText {
                    Text(statusMessage)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.coral)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var showsNotForSale: Bool {
        !SAVEProAccessPolicy.purchasingIsAvailable
            || (didFinishProductLoad && storeKit.products.isEmpty)
    }

    private var hasStatusNotice: Bool {
        if let statusMessage {
            return statusMessage != notForSaleText
        }
        return false
    }

    @ViewBuilder
    private var offers: some View {
        if !SAVEProAccessPolicy.purchasingIsAvailable {
            fallbackOffers(products: [])
        } else if storeKit.products.isEmpty, !didFinishProductLoad {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        } else if storeKit.products.isEmpty {
            fallbackOffers(products: [])
        } else {
            liveOffers(products: storeKit.products)
        }
    }

    private func fallbackOffers(products: [Product]) -> some View {
        continueButton(products: products)
    }

    private func liveOffers(products: [Product]) -> some View {
        continueButton(products: products)
    }

    private var notForSaleText: String {
        languageSettings.localized(
            english: "Pro isn't on sale yet",
            traditionalChinese: "Pro 尚未開賣"
        )
    }

    private func continueButton(products: [Product]) -> some View {
        let price = priceText(
            for: SAVEProAccessPolicy.ProductID.annual,
            products: products,
            fallback: "$39.99"
        )
        return Button {
            Task { await purchaseSelected() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(languageSettings.localized(
                        english: "Continue — \(price) / year",
                        traditionalChinese: "繼續 — \(price) / 年"
                    ))
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                SaveAtlasPalette.coral,
                in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
            )
        }
        .disabled(isPurchasing)
        .accessibilityIdentifier("paywall.continue")
    }

    private func priceText(for id: String, products: [Product], fallback: String) -> String {
        products.first(where: { $0.id == id })?.displayPrice ?? fallback
    }

    private func renewalDescription(for productID: String, products: [Product]) -> String {
        if let product = products.first(where: { $0.id == productID }) {
            return renewalDescription(for: product)
        }
        if productID == SAVEProAccessPolicy.ProductID.annual {
            return languageSettings.localized(
                english: "Auto-renews every 1 year. Cancel anytime.",
                traditionalChinese: "每 1 年自動續訂，可隨時取消。"
            )
        }
        return languageSettings.localized(
            english: "Auto-renews every 1 month. Cancel anytime.",
            traditionalChinese: "每 1 個月自動續訂，可隨時取消。"
        )
    }

    private func renewalDescription(for product: Product) -> String {
        guard let subscription = product.subscription else {
            return languageSettings.localized(english: "One-time", traditionalChinese: "一次性")
        }
        let period = subscription.subscriptionPeriod
        let unit: String
        switch period.unit {
        case .day:
            unit = languageSettings.localized(english: "day", traditionalChinese: "天")
        case .week:
            unit = languageSettings.localized(english: "week", traditionalChinese: "週")
        case .month:
            unit = languageSettings.localized(english: "month", traditionalChinese: "個月")
        case .year:
            unit = languageSettings.localized(english: "year", traditionalChinese: "年")
        @unknown default:
            unit = languageSettings.localized(english: "period", traditionalChinese: "期")
        }
        let count = period.value
        return languageSettings.localized(
            english: "Auto-renews every \(count) \(unit). Cancel anytime.",
            traditionalChinese: "每 \(count) \(unit)自動續訂，可隨時取消。"
        )
    }

    private var legalFooter: some View {
        VStack(spacing: SaveSpace.md) {
            Text(legalText)
                .font(SaveAtlasType.body(11))
                .foregroundStyle(SaveAtlasPalette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SaveSpace.lg) {
                Button {
                    Task { await restore() }
                } label: {
                    Text(languageSettings.localized(english: "Restore Purchases", traditionalChinese: "恢復購買"))
                }
                .accessibilityIdentifier("paywall.restore")

                if let terms = URL(string: SAVEProAccessPolicy.Legal.termsURL) {
                    Link(languageSettings.localized(english: "Terms", traditionalChinese: "使用條款"), destination: terms)
                        .accessibilityIdentifier("paywall.terms")
                }
                if let privacy = URL(string: SAVEProAccessPolicy.Legal.privacyURL) {
                    Link(languageSettings.localized(english: "Privacy", traditionalChinese: "隱私政策"), destination: privacy)
                        .accessibilityIdentifier("paywall.privacy")
                }
            }
            .font(SaveAtlasType.strong(13))
            .foregroundStyle(SaveAtlasPalette.coral)
            .tint(SaveAtlasPalette.coral)
            .frame(minHeight: SaveLayout.minTap)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("paywall.legal")
    }

    private var legalText: String {
        let renewal = renewalDescription(
            for: SAVEProAccessPolicy.ProductID.annual,
            products: storeKit.products
        )
        return languageSettings.localized(
            english: "\(renewal) Payment is charged to your Apple ID. Manage or cancel anytime in Settings › Apple ID › Subscriptions.",
            traditionalChinese: "\(renewal) 款項由你的 Apple ID 扣款。可在「設定 › Apple ID › 訂閱項目」中管理或取消。"
        )
    }

    private func purchaseSelected() async {
        guard SAVEProAccessPolicy.purchasingIsAvailable else {
            statusMessage = notForSaleText
            return
        }
        guard let product = storeKit.products.first(where: { $0.id == selectedProductID }) else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        switch await storeKit.purchase(product) {
        case .success:
            await SaveEntitlementStore.shared.refresh()
            SaveHaptics.stamp()
            dismiss()
        case .userCancelled:
            statusMessage = nil
        case .pending:
            statusMessage = languageSettings.localized(
                english: "Waiting for approval. You'll get access once it's confirmed.",
                traditionalChinese: "等待核准中。核准後就會開通。"
            )
        case .failed(let message):
            SaveHaptics.warning()
            statusMessage = message
        case .unavailable:
            statusMessage = languageSettings.localized(
                english: "Not available yet.",
                traditionalChinese: "尚未開放。"
            )
        }
    }

    private func restore() async {
        SaveHaptics.tap()
        switch await storeKit.restorePurchases() {
        case .success:
            await SaveEntitlementStore.shared.refresh()
            statusMessage = languageSettings.localized(
                english: "Purchases restored.",
                traditionalChinese: "已恢復購買。"
            )
        case .failed(let message):
            statusMessage = message
        case .unavailable:
            statusMessage = languageSettings.localized(
                english: "Nothing to restore yet.",
                traditionalChinese: "目前沒有可恢復的購買。"
            )
        case .userCancelled, .pending:
            break
        }
    }
}

private struct SaveDoodleForestCheck: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 4, y: 13))
            path.addQuadCurve(to: CGPoint(x: 10, y: 19), control: CGPoint(x: 6, y: 19))
            path.addQuadCurve(to: CGPoint(x: 21, y: 6), control: CGPoint(x: 14, y: 18))
        }
        .stroke(SaveAtlasPalette.forest, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

/// Bookmark stamp from the 2026-10-20 DESIGN paywall export (23cca55).
/// Path is the 48×48 SVG (`M12 6h24v36l-12-8-12 8z` + stampRed rings)
/// scaled into the 120pt lock.
private struct SaveDoodlePaywallStamp: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 48
            let sy = size.height / 48
            var bookmark = Path()
            bookmark.move(to: CGPoint(x: 12 * sx, y: 6 * sy))
            bookmark.addLine(to: CGPoint(x: 36 * sx, y: 6 * sy))
            bookmark.addLine(to: CGPoint(x: 36 * sx, y: 42 * sy))
            bookmark.addLine(to: CGPoint(x: 24 * sx, y: 34 * sy))
            bookmark.addLine(to: CGPoint(x: 12 * sx, y: 42 * sy))
            bookmark.closeSubpath()
            context.fill(bookmark, with: .color(SaveAtlasPalette.kraft))
            context.stroke(bookmark, with: .color(SaveAtlasPalette.ink), lineWidth: sx)
            let outer = Path(ellipseIn: CGRect(
                x: 17 * sx,
                y: 13 * sy,
                width: 14 * sx,
                height: 14 * sy
            ))
            let inner = Path(ellipseIn: CGRect(
                x: 19 * sx,
                y: 15 * sy,
                width: 10 * sx,
                height: 10 * sy
            ))
            context.stroke(outer, with: .color(SaveDoodle.stampRed), lineWidth: 1.2 * sx)
            context.stroke(inner, with: .color(SaveDoodle.stampRed), lineWidth: 1.2 * sx)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Paywall light") {
    SaveProPaywallView(trigger: .passport)
        .preferredColorScheme(.light)
}

#Preview("Paywall dark") {
    SaveProPaywallView(trigger: .passport)
        .preferredColorScheme(.dark)
}

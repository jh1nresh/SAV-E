import StoreKit
import SwiftUI

/// Pro paywall — Doodle v2 full-screen modal (DESIGN eade369).
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

            VStack(alignment: .leading, spacing: 0) {
                topBar
                hero
                    .padding(.top, SaveSpace.xs)
                headline
                    .padding(.top, SaveSpace.lg)
                benefitRow
                    .padding(.top, SaveSpace.md)
                savedNote
                    .padding(.top, SaveSpace.xs)
                Spacer(minLength: SaveSpace.md)
                    .overlay(alignment: .bottom) {
                        saleStateNotice
                            .padding(.bottom, SaveSpace.xs)
                    }
                offers
                legalFooter
                    .padding(.top, SaveSpace.sm)
            }
            .padding(.horizontal, SaveLayout.screenMargin)
            .padding(.bottom, SaveSpace.xs)
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
        ZStack {
            HStack(spacing: SaveSpace.xs) {
                SaveDisplayTitle(text: "Savvy", pointSize: 34, relativeTo: .largeTitle)
                SaveDoodleElephant(size: 28)
            }
            HStack {
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
                Spacer(minLength: 0)
            }
        }
        .frame(height: SaveLayout.minTap)
    }

    private var hero: some View {
        SaveDoodlePaywallHero()
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                    .stroke(SaveAtlasPalette.line, lineWidth: SaveAtlasPalette.strokeWidth)
            }
            .accessibilityHidden(true)
    }

    private var headline: some View {
        SaveDisplayTitle(
            text: languageSettings.localized(
                english: "Save every place you love",
                traditionalChinese: "想去的地方，全部存下"
            ),
            pointSize: 34,
            relativeTo: .title
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("paywall.header")
    }

    private var benefitRow: some View {
        HStack(spacing: SaveLayout.stickerToText) {
            Image(systemName: "bookmark")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(SaveAtlasPalette.ink)
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
        .frame(height: 36)
        .accessibilityIdentifier("paywall.benefit.unlimited")
    }

    private var savedNote: some View {
        Text(languageSettings.localized(
            english: "Keep saving the places you love.",
            traditionalChinese: "繼續收藏你喜歡的地方。"
        ))
        .font(SaveAtlasType.body(15))
        .foregroundStyle(SaveAtlasPalette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("paywall.savedNote")
    }

    /// Sale-state copy sits in the spacer so Yearly / Monthly / Continue
    /// stay on the DESIGN eade369 locks when purchasing is off.
    @ViewBuilder
    private var saleStateNotice: some View {
        if showsNotForSale || hasStatusNotice {
            VStack(alignment: .leading, spacing: SaveSpace.tight) {
                if showsNotForSale {
                    Text(notForSaleText)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("paywall.notForSale")
                }
                if let statusMessage, statusMessage != notForSaleText {
                    Text(statusMessage)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.coral)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(height: 52)
        } else if storeKit.products.isEmpty {
            fallbackOffers(products: [])
        } else {
            VStack(spacing: SaveSpace.sm) {
                planCards(products: storeKit.products)
                continueButton
            }
        }
    }

    private func fallbackOffers(products: [Product]) -> some View {
        VStack(spacing: SaveSpace.sm) {
            planCards(products: products)
            continueButton
        }
    }

    private var notForSaleText: String {
        languageSettings.localized(
            english: "Pro isn't on sale yet",
            traditionalChinese: "Pro 尚未開賣"
        )
    }

    private func planCards(products: [Product]) -> some View {
        VStack(spacing: SaveSpace.sm) {
            planCard(
                id: SAVEProAccessPolicy.ProductID.annual,
                title: languageSettings.localized(english: "Yearly", traditionalChinese: "年費"),
                price: priceText(
                    for: SAVEProAccessPolicy.ProductID.annual,
                    products: products,
                    fallback: "$39.99"
                ),
                symbol: "takeoutbag.and.cup.and.straw",
                showsBestValue: true
            )
            planCard(
                id: SAVEProAccessPolicy.ProductID.monthly,
                title: languageSettings.localized(english: "Monthly", traditionalChinese: "月費"),
                price: priceText(
                    for: SAVEProAccessPolicy.ProductID.monthly,
                    products: products,
                    fallback: "$6.99"
                ),
                symbol: "cup.and.saucer",
                showsBestValue: false
            )
        }
    }

    private func planCard(
        id: String,
        title: String,
        price: String,
        symbol: String,
        showsBestValue: Bool
    ) -> some View {
        let isSelected = id == selectedProductID
        return Button {
            SaveHaptics.select()
            selectedProductID = id
        } label: {
            HStack(spacing: SaveSpace.md) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.ink)
                    Text(price)
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.ink)
                }

                Spacer(minLength: 0)

                if showsBestValue {
                    Text(languageSettings.localized(english: "Best value", traditionalChinese: "最划算"))
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.coral)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(SaveAtlasPalette.coral, lineWidth: 1.2)
                        }
                }
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
                    .stroke(
                        isSelected ? SaveAtlasPalette.coral : SaveAtlasPalette.line,
                        lineWidth: isSelected ? 2 : SaveAtlasPalette.strokeWidth
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall.offer.\(id)")
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

    private var continueButton: some View {
        Button {
            Task { await purchaseSelected() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(languageSettings.localized(english: "Continue", traditionalChinese: "繼續"))
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                SaveAtlasPalette.coral,
                in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
            )
        }
        .disabled(isPurchasing)
        .padding(.top, SaveSpace.sm)
        .accessibilityIdentifier("paywall.continue")
    }

    private var legalFooter: some View {
        VStack(spacing: SaveSpace.xs) {
            Text(languageSettings.localized(
                english: "Payment is charged to your Apple Account. Subscriptions renew automatically unless cancelled at least 24 hours before the period ends. Manage or cancel in Settings.",
                traditionalChinese: "款項由你的 Apple 帳戶扣款。除非在到期前至少 24 小時取消，否則訂閱會自動續訂。可在「設定」中管理或取消。"
            ))
            .font(SaveAtlasType.body(11))
            .foregroundStyle(SaveAtlasPalette.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SaveSpace.xs) {
                Button {
                    Task { await restore() }
                } label: {
                    Text(languageSettings.localized(english: "Restore", traditionalChinese: "恢復購買"))
                }
                .accessibilityIdentifier("paywall.restore")

                footerDot
                if let terms = URL(string: SAVEProAccessPolicy.Legal.termsURL) {
                    Link(languageSettings.localized(english: "Terms", traditionalChinese: "使用條款"), destination: terms)
                        .accessibilityIdentifier("paywall.terms")
                }
                footerDot
                if let privacy = URL(string: SAVEProAccessPolicy.Legal.privacyURL) {
                    Link(languageSettings.localized(english: "Privacy", traditionalChinese: "隱私政策"), destination: privacy)
                        .accessibilityIdentifier("paywall.privacy")
                }
            }
            .font(SaveAtlasType.body(12))
            .foregroundStyle(SaveAtlasPalette.muted)
            .tint(SaveAtlasPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("paywall.legal")
    }

    private var footerDot: some View {
        Text("·")
            .foregroundStyle(SaveAtlasPalette.muted)
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

/// Illustrated city map for the paywall hero. Outline stickers wait to be
/// colored; one or two already have a stamp. Tiantan-shaped sample when the
/// user has no saved city yet.
struct SaveDoodlePaywallHero: View {
    var body: some View {
        ZStack {
            SaveAtlasPalette.paper
            SaveDoodlePaywallParkShape()
                .fill(SaveDoodle.washGreen.opacity(0.55))
            SaveDoodlePaywallPaths()
                .stroke(SaveAtlasPalette.line, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            sticker(.temple, x: 0.18, y: 0.28, visited: false)
            sticker(.noodle, x: 0.48, y: 0.30, visited: false)
            sticker(.coffee, x: 0.78, y: 0.26, visited: false)
            sticker(.duck, x: 0.16, y: 0.72, visited: false)
            sticker(.lantern, x: 0.74, y: 0.70, visited: true)

            ForEach(Array(treeOffsets.enumerated()), id: \.offset) { _, point in
                Image(systemName: "tree")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SaveAtlasPalette.forest.opacity(0.55))
                    .position(x: point.x, y: point.y)
            }
        }
        .background(SaveAtlasPalette.paper)
    }

    private var treeOffsets: [CGPoint] {
        [
            CGPoint(x: 36, y: 28),
            CGPoint(x: 92, y: 22),
            CGPoint(x: 168, y: 26),
            CGPoint(x: 248, y: 24),
            CGPoint(x: 310, y: 30),
            CGPoint(x: 54, y: 168),
            CGPoint(x: 300, y: 166),
        ]
    }

    private func sticker(
        _ kind: SaveDoodleOfficialSticker,
        x: CGFloat,
        y: CGFloat,
        visited: Bool
    ) -> some View {
        GeometryReader { geo in
            ZStack {
                Image(kind.imageName(visited: visited, pointSize: 48))
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                if visited {
                    Circle()
                        .stroke(SaveDoodle.stampRed, lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                }
            }
            .frame(width: 44, height: 44)
            .rotationEffect(.degrees(visited ? -5 : 4))
            .position(x: geo.size.width * x, y: geo.size.height * y)
        }
    }
}

nonisolated struct SaveDoodlePaywallParkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(
            x: rect.width * 0.28,
            y: rect.height * 0.18,
            width: rect.width * 0.46,
            height: rect.height * 0.44
        ))
        return path
    }
}

nonisolated struct SaveDoodlePaywallPaths: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.62))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.58),
            control: CGPoint(x: rect.width * 0.5, y: rect.height * 0.42)
        )
        path.move(to: CGPoint(x: rect.width * 0.18, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.72, y: rect.minY + 8),
            control: CGPoint(x: rect.width * 0.46, y: rect.height * 0.55)
        )
        return path
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

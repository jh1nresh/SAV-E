import StoreKit
import SwiftUI

/// Pro paywall — Doodle v2 full-screen modal (DESIGN eade369).
///
/// Opened from Settings / Passport, or from the 51st-save gate. Never
/// automatic, never at launch, never for an exhausted AI assist.
/// `SaveEntitlementStore.shouldPresentPaywall` stays false for AI refusals.
///
/// Pro v1 names one benefit: unlimited saved places. Quota headlines,
/// itinerary planning, and collectible extras stay off this screen.
/// Product IDs and purchase / restore logic are unchanged.
///
/// App Store review requirements that must stay on this screen: Restore
/// Purchases, EULA link, privacy policy link, renewal period, cancellation path.
struct SaveProPaywallView: View {
    enum Trigger: Equatable {
        /// Settings Pro row. Neutral copy, no save count.
        case settings
        /// Passport Pro row. Same neutral copy as settings (#293 name).
        case passport
        /// The 51st save. Names the free 50-place allowance.
        case savedPlacesCap
        /// A free save was parked in Unplaced because the 50-place cap is full.
        case savedPlaceLimit
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

            // Contain-on-ScrollView still dropped paywall.scroll on
            // AccessibilityXXXL and SE (run 40055307655). Keep the
            // identifier on a VStack wrapper, not the ScrollView.
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar
                        hero
                            .padding(.top, SaveSpace.xs)
                        headline
                            .padding(.top, SaveSpace.lg)
                        freeTierLine
                            .padding(.top, SaveSpace.xs)
                        benefitRow
                            .padding(.top, SaveSpace.md)
                        savedNote
                            .padding(.top, SaveSpace.xs)
                        offers
                            .padding(.top, SaveSpace.md)
                        if let statusMessage {
                            Text(statusMessage)
                                .font(SaveAtlasType.body(13))
                                .foregroundStyle(SaveAtlasPalette.coral)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, SaveSpace.xs)
                        }
                        legalFooter
                            .padding(.top, SaveSpace.sm)
                    }
                    .padding(.horizontal, SaveLayout.screenMargin)
                    .padding(.bottom, SaveSpace.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("paywall.scroll")
        }
        .presentationBackground(SaveAtlasPalette.canvas)
        .interactiveDismissDisabled(isPurchasing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.root")
        .accessibilityValue(showsSavedPlaceNote ? "savedPlacesCap" : "settings")
        .task {
            await refreshProducts()
        }
    }

    private var topBar: some View {
        ZStack {
            HStack(spacing: SaveSpace.xs) {
                SaveDisplayTitle(text: "Savvy", pointSize: 34, relativeTo: .largeTitle)
                MemoMascotMark(size: 28, framed: false)
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

    /// One free-tier sentence on every entry. The 51st-save `savedNote`
    /// is separate and must not repeat this line.
    private var freeTierLine: some View {
        Text(languageSettings.localized(
            english: "Free: 50 places",
            traditionalChinese: "免費：50 個地點"
        ))
        .font(SaveAtlasType.body(15))
        .foregroundStyle(SaveAtlasPalette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var benefitRow: some View {
        let title = languageSettings.localized(
            english: "Unlimited saved places",
            traditionalChinese: "無限收藏地點"
        )
        return HStack(spacing: SaveLayout.stickerToText) {
            Image(systemName: "bookmark")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(SaveAtlasPalette.ink)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(SaveAtlasType.strong(17))
                .foregroundStyle(SaveAtlasPalette.ink)
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.benefit.unlimited")
        .accessibilityLabel(title)
    }

    private var showsSavedPlaceNote: Bool {
        if trigger == .savedPlaceLimit { return true }
        return trigger == .savedPlacesCap
    }

    @ViewBuilder
    private var savedNote: some View {
        if trigger == .savedPlaceLimit {
            Text(languageSettings.localized(
                english: "You've saved 50 places. Keep going.",
                traditionalChinese: "已存 50 個地點，繼續存下去"
            ))
            .font(SaveAtlasType.body(15))
            .foregroundStyle(SaveAtlasPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("paywall.savedNote")
        } else if trigger == .savedPlacesCap {
            Text(languageSettings.localized(
                english: SaveProPaywallCopy.savedNote(for: trigger, english: true),
                traditionalChinese: SaveProPaywallCopy.savedNote(for: trigger, english: false)
            ))
            .font(SaveAtlasType.body(15))
            .foregroundStyle(SaveAtlasPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("paywall.savedNote")
        }
    }

    @ViewBuilder
    private var offers: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-show-paywall-retry") {
            retryOffers(
                message: languageSettings.localized(
                    english: "Couldn't load subscription options.",
                    traditionalChinese: "無法載入訂閱方案。"
                )
            )
        } else {
            liveOffers
        }
#else
        liveOffers
#endif
    }

    @ViewBuilder
    private var liveOffers: some View {
        if storeKit.products.isEmpty, !didFinishProductLoad {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .accessibilityIdentifier("paywall.loading")
        } else if storeKit.products.isEmpty {
            unavailableRetry
        } else {
            VStack(spacing: SaveSpace.sm) {
                planCards(products: storeKit.products)
                continueButton
            }
        }
    }

    private var unavailableRetry: some View {
        VStack(alignment: .leading, spacing: SaveSpace.sm) {
            Text(languageSettings.localized(
                english: "Plans are unavailable right now.",
                traditionalChinese: "目前無法載入方案"
            ))
            .font(SaveAtlasType.body(15))
            .foregroundStyle(SaveAtlasPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("paywall.unavailable")

            Button {
                Task { await refreshProducts() }
            } label: {
                Text(languageSettings.localized(english: "Retry", traditionalChinese: "再試一次"))
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        SaveAtlasPalette.coral,
                        in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paywall.retry")
        }
    }

    @ViewBuilder
    private func retryOffers(message: String) -> some View {
        VStack(alignment: .leading, spacing: SaveSpace.sm) {
            Text(message)
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("paywall.unavailable")

            Button {
                Task { await refreshProducts() }
            } label: {
                Text(languageSettings.localized(english: "Try again", traditionalChinese: "再試一次"))
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        SaveAtlasPalette.coral,
                        in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paywall.retry")
        }
    }

    private func refreshProducts() async {
        didFinishProductLoad = false
        await storeKit.loadProducts()
        didFinishProductLoad = true
        if storeKit.products.contains(where: { $0.id == SAVEProAccessPolicy.ProductID.annual }) {
            selectedProductID = SAVEProAccessPolicy.ProductID.annual
        } else if storeKit.products.contains(where: { $0.id == SAVEProAccessPolicy.ProductID.monthly }) {
            selectedProductID = SAVEProAccessPolicy.ProductID.monthly
        }
    }

    private func planCards(products: [Product]) -> some View {
        VStack(spacing: SaveSpace.sm) {
            planCard(
                id: SAVEProAccessPolicy.ProductID.annual,
                title: languageSettings.localized(english: "Yearly", traditionalChinese: "年費"),
                price: priceText(
                    for: SAVEProAccessPolicy.ProductID.annual,
                    products: products
                ),
                sticker: .noodle,
                showsBestValue: true,
                products: products
            )
            planCard(
                id: SAVEProAccessPolicy.ProductID.monthly,
                title: languageSettings.localized(english: "Monthly", traditionalChinese: "月費"),
                price: priceText(
                    for: SAVEProAccessPolicy.ProductID.monthly,
                    products: products
                ),
                sticker: .coffee,
                showsBestValue: false,
                products: products
            )
        }
    }

    private func planCard(
        id: String,
        title: String,
        price: String,
        sticker: SaveDoodleOfficialSticker,
        showsBestValue: Bool,
        products: [Product]
    ) -> some View {
        let isSelected = id == selectedProductID
        return Button {
            SaveHaptics.select()
            selectedProductID = id
        } label: {
            HStack(spacing: SaveSpace.md) {
                Image(sticker.imageName(visited: true, pointSize: 48))
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.ink)
                    Text(price)
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.ink)
                    Text(renewalDescription(for: id, products: products))
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("paywall.renewal.\(id)")
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
            .padding(.vertical, SaveSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: SaveLayout.rowMinHeight)
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

    private func priceText(for id: String, products: [Product]) -> String {
        products.first(where: { $0.id == id })?.displayPrice ?? ""
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
        guard SAVEProAccessPolicy.purchasingIsAvailable else { return }
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

/// Illustrated city map for the paywall hero. Colored official stickers
/// plus a pencil on the park. Tiantan-shaped sample when the user has no
/// saved city yet.
struct SaveDoodlePaywallHero: View {
    var body: some View {
        ZStack {
            SaveAtlasPalette.paper
            SaveDoodlePaywallParkShape()
                .fill(SaveDoodle.washGreen.opacity(0.55))
            SaveDoodlePaywallPaths()
                .stroke(SaveAtlasPalette.line, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            pencilMark(x: 0.18, y: 0.28)
            sticker(.noodle, x: 0.48, y: 0.30, visited: true)
            sticker(.coffee, x: 0.78, y: 0.26, visited: true)
            sticker(.duck, x: 0.16, y: 0.72, visited: true)
            sticker(.lantern, x: 0.74, y: 0.70, visited: true)

            ForEach(Array(treeOffsets.enumerated()), id: \.offset) { _, point in
                Image(systemName: "tree")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SaveAtlasPalette.forest.opacity(0.55))
                    .position(x: point.x, y: point.y)
                    .accessibilityHidden(true)
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

    private func pencilMark(x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { geo in
            Image(systemName: "pencil")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(SaveAtlasPalette.ink)
                .rotationEffect(.degrees(-28))
                .position(x: geo.size.width * x, y: geo.size.height * y)
                .accessibilityHidden(true)
        }
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
            .accessibilityHidden(true)
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
    SaveProPaywallView(trigger: .settings)
        .preferredColorScheme(.light)
}

#Preview("Paywall dark") {
    SaveProPaywallView(trigger: .settings)
        .preferredColorScheme(.dark)
}

/// Supporting note only. Headline and benefit stay the same on both entries.
nonisolated enum SaveProPaywallCopy {
    static func savedNote(for trigger: SaveProPaywallView.Trigger, english: Bool) -> String {
        switch trigger {
        case .savedPlacesCap, .savedPlaceLimit:
            return english
                ? "You've saved 50 places. Keep going."
                : "已存 50 個地點，繼續存下去"
        case .settings, .passport:
            return ""
        }
    }
}

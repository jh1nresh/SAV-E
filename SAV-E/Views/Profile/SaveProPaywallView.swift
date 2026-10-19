import StoreKit
import SwiftUI

/// Savvy Pro paywall.
///
/// Presented only as a reaction to a refused AI assist, or pulled up
/// deliberately from Passport. Never automatic, never at launch, never before
/// the first confirmed Map Stamp — `SaveEntitlementStore.shouldPresentPaywall`
/// enforces that and this view does not second-guess it.
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
    @State private var isRestoring = false
    @State private var isPurchasing = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SaveTheme.Spacing.xl) {
                    header
                    boundaryPanel
                    offers
                    operationStatus
                    accountNotice
                    legalFooter
                }
                .padding(SaveTheme.Spacing.lg)
            }
            .background(SaveAtlasPalette.canvas.ignoresSafeArea())
            .toolbar {
                // Always dismissable. A subscription sheet the user cannot
                // close is an App Store rejection and a dark pattern.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        SaveHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SaveAtlasPalette.ink)
                    }
                    .accessibilityIdentifier("paywall.close")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await restore() }
                    } label: {
                        Text(languageSettings.localized(
                            english: "Restore",
                            traditionalChinese: "恢復購買"
                        ))
                        .font(SaveTheme.Typography.supporting)
                        .foregroundStyle(SaveAtlasPalette.forest)
                    }
                    .disabled(isRestoring || isPurchasing)
                    .accessibilityIdentifier("paywall.restore")
                }
            }
        }
        .accessibilityIdentifier("paywall.root")
        .task { await storeKit.loadProducts() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            Text(languageSettings.localized(english: "Savvy PRO", traditionalChinese: "Savvy PRO"))
                .font(SaveTheme.Typography.eyebrow)
                .foregroundStyle(SaveAtlasPalette.muted)

            Text(headline)
                .font(SaveAtlasType.display(28))
                .foregroundStyle(SaveAtlasPalette.forest)

            Text(subheadline)
                .font(SaveAtlasType.body(14))
                .foregroundStyle(SaveAtlasPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("paywall.header")
    }

    private var headline: String {
        switch trigger {
        case .aiAssistExhausted:
            return languageSettings.localized(
                english: "You've used this month's AI assists",
                traditionalChinese: "這個月的 AI 協助已用完"
            )
        case .passport:
            return languageSettings.localized(
                english: "More AI, same private map",
                traditionalChinese: "更多 AI，同一張私人地圖"
            )
        }
    }

    private var subheadline: String {
        languageSettings.localized(
            english: "Your saved places, Map Stamps, and private map stay free and unlimited. Pro raises the monthly allowance for the parts that call a model.",
            traditionalChinese: "你收藏的地點、Map Stamp 與私人地圖永遠免費且無上限。Pro 只提高需要呼叫模型的每月額度。"
        )
    }

    /// The free/paid boundary is stated plainly. Hiding it would make the
    /// refusal feel arbitrary and invite refund requests.
    private var boundaryPanel: some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.md) {
            boundaryGroup(
                title: languageSettings.localized(english: "Always free", traditionalChinese: "永遠免費"),
                tint: SaveAtlasPalette.mint,
                items: [
                    languageSettings.localized(english: "Unlimited saved places and Map Stamps", traditionalChinese: "無限收藏地點與 Map Stamp"),
                    languageSettings.localized(english: "Your private map and notebooks", traditionalChinese: "你的私人地圖與筆記本"),
                    languageSettings.localized(english: "Search across everything you saved", traditionalChinese: "搜尋你收藏過的所有內容")
                ]
            )

            boundaryGroup(
                title: languageSettings.localized(english: "Counts as an AI assist", traditionalChinese: "計入 AI 協助"),
                tint: SaveAtlasPalette.lavender,
                items: [
                    languageSettings.localized(english: "Link parsing that can't be resolved locally", traditionalChinese: "無法在本機解析的連結")
                ]
            )
        }
        .padding(SaveTheme.Spacing.lg)
        .background(SaveAtlasPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
        )
        .accessibilityIdentifier("paywall.boundary")
    }

    private func boundaryGroup(title: String, tint: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            Text(title)
                .font(SaveTheme.Typography.sectionLabel)
                .foregroundStyle(SaveAtlasPalette.ink)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: SaveTheme.Spacing.sm) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    Text(item)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var offers: some View {
        switch Self.productPresentation(
            purchasingAvailable: SAVEProAccessPolicy.purchasingIsAvailable,
            hasProducts: !storeKit.products.isEmpty,
            isLoading: storeKit.isLoadingProducts,
            hasError: storeKit.lastError != nil
        ) {
        case .notForSale:
            // Honest empty state. Showing a dead "Subscribe" button before the
            // products exist would imply a transaction that cannot happen.
            VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                Text(languageSettings.localized(
                    english: "Pro isn't on sale yet",
                    traditionalChinese: "Pro 尚未開賣"
                ))
                .font(SaveTheme.Typography.cardTitle)
                .foregroundStyle(SaveAtlasPalette.forest)

                Text(languageSettings.localized(
                    english: "Everything above is free while Savvy is in TestFlight. Nothing is charged and no allowance is enforced.",
                    traditionalChinese: "Savvy 在 TestFlight 期間以上功能全部免費，不會收費，也不會限制額度。"
                ))
                .font(SaveAtlasType.body(13))
                .foregroundStyle(SaveAtlasPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SaveTheme.Spacing.lg)
            .background(SaveAtlasPalette.mint.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("paywall.notForSale")
        case .loading:
            ProgressView(languageSettings.localized(
                english: "Loading subscription options…",
                traditionalChinese: "正在載入訂閱方案…"
            ))
                .frame(maxWidth: .infinity)
                .padding(.vertical, SaveTheme.Spacing.xl)
                .accessibilityIdentifier("paywall.loading")
        case .failed:
            unavailableProducts(failed: true)
        case .unavailable:
            unavailableProducts(failed: false)
        case .available:
            VStack(spacing: SaveTheme.Spacing.md) {
                ForEach(storeKit.products, id: \.id) { product in
                    offerRow(product)
                }

                Button {
                    Task { await purchaseSelected() }
                } label: {
                    if isPurchasing {
                        ProgressView().tint(SaveTheme.Colors.nearBlack)
                    } else {
                        Text(languageSettings.localized(english: "Continue", traditionalChinese: "繼續"))
                    }
                }
                .buttonStyle(SaveBrandPrimaryButtonStyle(fill: SaveAtlasPalette.honey))
                .disabled(isPurchasing || isRestoring)
                .accessibilityIdentifier("paywall.continue")
            }
        }
    }

    enum ProductPresentation: Equatable {
        case notForSale, loading, failed, unavailable, available
    }

    /// Loading takes precedence over the previous error during a retry.
    static func productPresentation(
        purchasingAvailable: Bool, hasProducts: Bool, isLoading: Bool, hasError: Bool
    ) -> ProductPresentation {
        guard purchasingAvailable else { return .notForSale }
        if hasProducts { return .available }
        if isLoading { return .loading }
        return hasError ? .failed : .unavailable
    }

    private func unavailableProducts(failed: Bool) -> some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.md) {
            Text(failed
                 ? languageSettings.localized(english: "Couldn't load subscription options", traditionalChinese: "無法載入訂閱方案")
                 : languageSettings.localized(english: "Subscription options aren't available yet", traditionalChinese: "訂閱方案目前尚不可用"))
                .font(SaveTheme.Typography.cardTitle)
                .foregroundStyle(SaveAtlasPalette.forest)
            Text(languageSettings.localized(
                english: "Try again later. You can still save places and use your private map.",
                traditionalChinese: "請稍後重試。你仍可收藏地點並使用私人地圖。"
            ))
            .font(SaveAtlasType.body(13))
            .foregroundStyle(SaveAtlasPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await storeKit.loadProducts() }
            } label: {
                Text(languageSettings.localized(english: "Try again", traditionalChinese: "重試"))
            }
            .buttonStyle(SaveBrandPrimaryButtonStyle(fill: SaveAtlasPalette.honey))
            .disabled(storeKit.isLoadingProducts || isPurchasing || isRestoring)
            .accessibilityIdentifier("paywall.retryProducts")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SaveTheme.Spacing.lg)
        .background(SaveAtlasPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier(failed ? "paywall.productsFailed" : "paywall.productsUnavailable")
    }

    /// Operation feedback must remain visible even without products or sales enabled.
    @ViewBuilder
    private var operationStatus: some View {
        if isRestoring {
            ProgressView(languageSettings.localized(english: "Restoring purchases…", traditionalChinese: "正在恢復購買…"))
        }
        if let statusMessage {
            Text(statusMessage)
                .font(SaveTheme.Typography.supporting)
                .foregroundStyle(SaveAtlasPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.status")
        }
    }

    private var accountNotice: some View {
        Text(languageSettings.localized(
            english: "Pro is linked to the Savvy account used at purchase. To restore on another device, sign in to that same Savvy account and the Apple Account used to purchase. Restoring does not automatically transfer Pro to a different Savvy account.",
            traditionalChinese: "Pro 綁定購買時使用的 Savvy 帳號。若要在其他裝置恢復，請登入同一個 Savvy 帳號及原購買的 Apple 帳戶。恢復購買不會自動將 Pro 轉移至其他 Savvy 帳號。"
        ))
        .font(SaveAtlasType.body(13))
        .foregroundStyle(SaveAtlasPalette.muted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("paywall.accountBinding")
    }

    private func offerRow(_ product: Product) -> some View {
        let isSelected = product.id == selectedProductID
        return Button {
            SaveHaptics.select()
            selectedProductID = product.id
        } label: {
            HStack(spacing: SaveTheme.Spacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? SaveAtlasPalette.forest : SaveAtlasPalette.line)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(SaveAtlasType.strong(15))
                        .foregroundStyle(SaveAtlasPalette.forest)
                    // Renewal terms must be visible before purchase.
                    Text(renewalDescription(for: product))
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(SaveAtlasType.strong(15))
                    .foregroundStyle(SaveAtlasPalette.ink)
            }
            .padding(SaveTheme.Spacing.lg)
            .background(isSelected ? SaveAtlasPalette.mint.opacity(0.3) : SaveAtlasPalette.paper)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? SaveAtlasPalette.forest.opacity(0.5) : SaveAtlasPalette.line.opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall.offer.\(product.id)")
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
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            Text(languageSettings.localized(
                english: "Payment is charged to your Apple Account. Subscriptions renew automatically unless cancelled at least 24 hours before the period ends. Manage or cancel in Settings.",
                traditionalChinese: "款項由你的 Apple 帳戶扣款。除非在到期前至少 24 小時取消，否則訂閱會自動續訂。可在「設定」中管理或取消。"
            ))
            .font(SaveAtlasType.body(11))
            .foregroundStyle(SaveAtlasPalette.muted)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SaveTheme.Spacing.lg) {
                if let terms = URL(string: SAVEProAccessPolicy.Legal.termsURL) {
                    Link(languageSettings.localized(english: "Terms (EULA)", traditionalChinese: "使用條款"), destination: terms)
                        .accessibilityIdentifier("paywall.terms")
                }
                if let privacy = URL(string: SAVEProAccessPolicy.Legal.privacyURL) {
                    Link(languageSettings.localized(english: "Privacy", traditionalChinese: "隱私政策"), destination: privacy)
                        .accessibilityIdentifier("paywall.privacy")
                }
                if let manage = URL(string: SAVEProAccessPolicy.Legal.manageSubscriptionsURL) {
                    Link(languageSettings.localized(english: "Manage", traditionalChinese: "管理訂閱"), destination: manage)
                        .accessibilityIdentifier("paywall.manage")
                }
            }
            .font(SaveAtlasType.body(11))
            .tint(SaveAtlasPalette.forest)
        }
        .accessibilityIdentifier("paywall.legal")
    }

    // MARK: - Actions

    private func purchaseSelected() async {
        guard let product = storeKit.products.first(where: { $0.id == selectedProductID }) else { return }
        guard !isPurchasing, !isRestoring else { return }
        statusMessage = nil
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
        guard !isRestoring, !isPurchasing else { return }
        isRestoring = true
        statusMessage = nil
        defer { isRestoring = false }
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
                english: "Restoring purchases is not available right now. Please try again later.",
                traditionalChinese: "目前無法恢復購買，請稍後再試。"
            )
        case .userCancelled:
            statusMessage = languageSettings.localized(english: "Restore cancelled.", traditionalChinese: "已取消恢復購買。")
        case .pending:
            statusMessage = languageSettings.localized(
                english: "Restore is awaiting confirmation. Pro has not been activated yet.",
                traditionalChinese: "恢復購買仍在等待確認，Pro 尚未開通。"
            )
        }
    }
}

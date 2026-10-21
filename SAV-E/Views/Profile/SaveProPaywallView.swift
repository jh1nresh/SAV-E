import StoreKit
import SwiftUI

/// Savvy Pro paywall.
///
/// Presented for a parked 51st free save, or pulled up deliberately from
/// Passport. Never an automatic first-launch wall. Exhausted model allowance
/// is a neutral notice, not this sheet. A Share Extension save over the free
/// cap sets a pending handoff so this sheet can open the next time the app
/// becomes active.
///
/// App Store review requirements that must stay on this screen: Restore
/// Purchases, EULA link, privacy policy link, renewal period, cancellation path.
struct SaveProPaywallView: View {
    enum Trigger: Equatable {
        /// The user opened Pro from Passport.
        case passport
        /// A free save was parked in Review because the 50-place cap is full.
        case savedPlaceLimit
    }

    let trigger: Trigger

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings

    @State private var storeKit = SaveStoreKitService.shared
    @State private var selectedProductID: String = SAVEProAccessPolicy.ProductID.annual
    @State private var isPurchasing = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SaveTheme.Spacing.xl) {
                    header
                    boundaryPanel
                    offers
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

            SaveDisplayTitle(text: headline, pointSize: 34)

            Text(subheadline)
                .font(SaveAtlasType.body(14))
                .foregroundStyle(SaveAtlasPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.freePlaceLimit")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.header")
    }

    private var headline: String {
        languageSettings.localized(
            english: "Save every place you love",
            traditionalChinese: "想去的地方，全部存下"
        )
    }

    private var subheadline: String {
        languageSettings.localized(
            english: "Free: 50 places",
            traditionalChinese: "免費：50 個地點"
        )
    }

    /// DESIGN §7.6: one free-tier line, one Pro benefit, and a keep-going note
    /// only for the cap trigger. The free-tier sentence appears only in
    /// `subheadline`.
    private var boundaryPanel: some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            HStack(alignment: .top, spacing: SaveTheme.Spacing.sm) {
                Circle()
                    .fill(SaveAtlasPalette.lavender)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                Text(languageSettings.localized(
                    english: "Unlimited saved places",
                    traditionalChinese: "無限收藏地點"
                ))
                .font(SaveAtlasType.body(13))
                .foregroundStyle(SaveAtlasPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityIdentifier("paywall.proBenefit")

            if trigger == .savedPlaceLimit {
                Text(languageSettings.localized(
                    english: "You've saved 50 places. Keep going.",
                    traditionalChinese: "已存 50 個地點，繼續存下去"
                ))
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.keepGoing")
            }
        }
        .padding(SaveTheme.Spacing.lg)
        .background(SaveAtlasPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.boundary")
    }

    @ViewBuilder
    private var offers: some View {
        if !SAVEProAccessPolicy.purchasingIsAvailable {
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
                    english: "Purchasing isn't live yet.",
                    traditionalChinese: "目前還不能購買。"
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
        } else if storeKit.products.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, SaveTheme.Spacing.xl)
        } else {
            VStack(spacing: SaveTheme.Spacing.md) {
                ForEach(storeKit.products, id: \.id) { product in
                    offerRow(product)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(SaveTheme.Typography.supporting)
                        .foregroundStyle(SaveAtlasPalette.coral)
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
                .disabled(isPurchasing)
                .accessibilityIdentifier("paywall.continue")
            }
        }
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

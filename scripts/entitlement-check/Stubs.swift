import Foundation

/// Isolated `swiftc` host for `SaveEntitlementStore` does not compile AppLanguageSettings.
enum AppLanguage {
    case english
    case traditionalChinese
}

@MainActor final class PrivyAuthService {
    static let shared = PrivyAuthService()
    var sessionGeneration = 1
    var currentUserId: String? = "fixture-owner"
}
@MainActor final class SupabaseService {
    static let shared = SupabaseService()
    func fetchPurchaseAccountToken() async throws -> UUID { fatalError("Live token request forbidden in host checks") }
    func registerAppleTransaction(signedTransaction: String) async throws -> SaveEntitlementResponse { fatalError("Live registration forbidden in host checks") }
    func fetchUsageQuotaPreview() async throws -> SaveUsageQuotaPreview { fatalError("Live quota forbidden in host checks") }
}

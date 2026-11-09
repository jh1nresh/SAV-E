import Foundation
@main struct EntitlementHostCheck {
    @MainActor static func main() async throws {
        let count = try await SaveEntitlementRegressionChecks.run()
        print("entitlement-check: \(count) behavioral cases passed; no Apple/provider calls")
    }
}

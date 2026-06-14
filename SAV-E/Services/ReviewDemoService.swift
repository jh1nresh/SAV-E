import Foundation

// MARK: - App Review Demo Account
//
// This is an **App Store / Beta App Review demo account**. Apple's reviewers
// cannot receive a real email OTP, so the normal Privy sign-in flow locks them
// out. The constant credentials below let a reviewer enter a fully-populated,
// isolated demo session (backend guest token + locally-seeded places) without a
// real Privy account.
//
// Security: only the EXACT (email, code) pair below triggers the bypass — every
// other email/code goes through the normal Privy flow unchanged. The demo
// session has no access to real users' data: it is backed by an anonymous guest
// token plus local seed data only.
//
// This account can be rotated or removed after approval — change the constants
// here (and the App Store Connect "Sign-In Information" notes) or delete the
// bypass branch in `PrivyAuthService`.
enum ReviewDemo {
    /// Demo email the reviewer types into the email sign-in field.
    static let email = "appreview@wanderly.app"

    /// Demo verification code the reviewer types into the code field.
    static let code = "424242"

    /// Stable user id used for the demo `authState`. Not a real Privy id.
    static let userId = "review-demo"

    /// UserDefaults flag so the local vault is only seeded once (idempotent).
    static let seededDefaultsKey = "reviewDemoSeeded"

    /// Case-insensitive, whitespace-trimmed match on the email so the reviewer
    /// isn't tripped up by autocapitalization or trailing spaces.
    static func isDemoEmail(_ value: String) -> Bool {
        normalized(value) == email
    }

    /// Exact pair check: BOTH the demo email and the demo code must match for
    /// the bypass to fire. Everything else falls through to Privy.
    static func isDemoCredentialPair(email: String, code: String) -> Bool {
        isDemoEmail(email) && normalized(code) == self.code
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Guest Token Holder

/// Thread-safe holder for the demo guest token so the (synchronous, actor-free)
/// `guestTokenProvider` closure on `SAVEGeminiTransport` can read it without
/// hopping to the main actor. The token is written once on demo entry.
final class ReviewDemoGuestTokenHolder: @unchecked Sendable {
    static let shared = ReviewDemoGuestTokenHolder()

    private let lock = NSLock()
    private var token: String?

    var current: String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    func set(_ value: String?) {
        lock.lock(); defer { lock.unlock() }
        token = value
    }
}

// MARK: - Demo Seed Data

enum ReviewDemoSeed {
    /// ~6 realistic places across regions so the map + passport are populated
    /// immediately when the reviewer enters demo mode. Coordinates, category, a
    /// short note, and a source platform are all set so map pins + place detail
    /// render fully.
    static func places(now: Date = Date()) -> [Place] {
        [
            Place(
                id: UUID(),
                name: "Ichiran Shibuya",
                address: "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
                latitude: 35.6615,
                longitude: 139.6996,
                category: .food,
                status: .visited,
                rating: 4.6,
                note: "Tonkotsu ramen, order extra firm noodles. Solo booth seating.",
                sourcePlatform: .instagram,
                createdAt: now.addingTimeInterval(-6 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Classic tonkotsu", "Private solo booths"],
                vibeTags: ["cozy", "late-night"],
                sourceHandle: "tokyo.eats"
            ),
            Place(
                id: UUID(),
                name: "Fujin Tree 353 Cafe",
                address: "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei",
                latitude: 25.0411,
                longitude: 121.5436,
                category: .cafe,
                status: .wantToGo,
                rating: 4.5,
                note: "Pour-over + cheesecake. Plant-filled corner spot, great for working.",
                sourcePlatform: .xiaohongshu,
                createdAt: now.addingTimeInterval(-5 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Single-origin pour-over", "Window seats"],
                vibeTags: ["quiet", "work-friendly"],
                sourceHandle: "taipei.cafe.hop"
            ),
            Place(
                id: UUID(),
                name: "Guerrilla Tacos",
                address: "2000 E 7th St, Los Angeles, CA 90021",
                latitude: 34.0335,
                longitude: -118.2310,
                category: .food,
                status: .wantToGo,
                rating: 4.4,
                note: "Sweet potato taco is the move. Get there before the lunch rush.",
                sourcePlatform: .instagram,
                createdAt: now.addingTimeInterval(-4 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Sweet potato taco", "Chef-driven menu"],
                vibeTags: ["casual", "lunch"],
                sourceHandle: "la.taco.guide"
            ),
            Place(
                id: UUID(),
                name: "The Siam Hotel",
                address: "3/2 Thanon Khao, Vachiraphayaban, Dusit, Bangkok 10300",
                latitude: 13.7842,
                longitude: 100.5072,
                category: .stay,
                status: .wantToGo,
                rating: 4.8,
                note: "Riverside art-deco hotel. Pool villas, ferry to the old town.",
                sourcePlatform: .other,
                createdAt: now.addingTimeInterval(-3 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Riverside villas", "Art-deco design"],
                vibeTags: ["luxury", "riverside"],
                sourceHandle: "bangkok.stays"
            ),
            Place(
                id: UUID(),
                name: "Bar Benfiddich",
                address: "9F, 1-13-7 Nishishinjuku, Shinjuku City, Tokyo",
                latitude: 35.6938,
                longitude: 139.6970,
                category: .bar,
                status: .wantToGo,
                rating: 4.7,
                note: "Herb-forward cocktails, the bartender grinds botanicals tableside.",
                sourcePlatform: .threads,
                createdAt: now.addingTimeInterval(-2 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["House botanicals", "Reservation recommended"],
                vibeTags: ["intimate", "date-night"],
                sourceHandle: "tokyo.nightcap"
            ),
            Place(
                id: UUID(),
                name: "Daan Forest Park",
                address: "Section 2, Xinyi Rd, Da'an District, Taipei",
                latitude: 25.0297,
                longitude: 121.5354,
                category: .attraction,
                status: .visited,
                rating: 4.6,
                note: "City's green lung. Morning walk loop and an open-air amphitheatre.",
                sourcePlatform: .googleMaps,
                createdAt: now.addingTimeInterval(-1 * 86_400),
                visibility: .privateMemory,
                placeHighlights: ["Walking loop", "Open-air amphitheatre"],
                vibeTags: ["outdoors", "relaxed"],
                sourceHandle: "taipei.outdoors"
            ),
        ]
    }
}

# Wanderly iOS - Swift Project Scaffold

## What to Build
Scaffold a complete iOS app project for "Wanderly" — an AI-powered place discovery and trip planning app.

## Project Structure Required

```
Wanderly/
├── Wanderly.xcodeproj/          (or use Swift Package if simpler)
├── Wanderly/
│   ├── App/
│   │   ├── WanderlyApp.swift       (main app entry)
│   │   └── ContentView.swift        (tab-based root view)
│   ├── Views/
│   │   ├── Map/
│   │   │   ├── MapView.swift        (main map with pins, clustering)
│   │   │   └── PlaceBottomSheet.swift
│   │   ├── List/
│   │   │   ├── PlaceListView.swift  (filterable list with cards)
│   │   │   └── PlaceCard.swift
│   │   ├── Trips/
│   │   │   ├── TripPlannerView.swift
│   │   │   └── TripTimelineCard.swift
│   │   ├── Profile/
│   │   │   ├── ProfileView.swift
│   │   │   └── StatsView.swift
│   │   ├── Detail/
│   │   │   └── PlaceDetailView.swift
│   │   ├── Onboarding/
│   │   │   └── OnboardingView.swift (3-step carousel)
│   │   └── Shared/
│   │       ├── CategoryPill.swift
│   │       ├── EmptyStateView.swift
│   │       └── PlatformIcon.swift
│   ├── Models/
│   │   ├── Place.swift              (SavedPlace data model)
│   │   ├── Trip.swift
│   │   └── UserProfile.swift
│   ├── Services/
│   │   ├── AIParsingService.swift   (Claude Vision API integration)
│   │   ├── GooglePlacesService.swift
│   │   ├── SupabaseService.swift
│   │   └── PrivyAuthService.swift
│   ├── ViewModels/
│   │   ├── MapViewModel.swift
│   │   ├── PlaceListViewModel.swift
│   │   ├── TripViewModel.swift
│   │   └── ProfileViewModel.swift
│   ├── Extensions/
│   │   └── Color+Theme.swift       (Wanderly color theme)
│   └── Resources/
│       └── Assets.xcassets
├── WanderlyShareExtension/
│   ├── ShareViewController.swift    (Share Extension entry)
│   └── Info.plist
├── WanderlyClip/
│   ├── WanderlyClipApp.swift        (App Clip entry)
│   └── ClipContentView.swift
├── .env.example
├── README.md
└── .gitignore
```

## Design Theme
- Cream/ivory background: #FFF8F0
- Terracotta accent: #C75B39
- Sage secondary: #A8B5A0
- Dark charcoal text: #2C2C2E
- Dark mode: charcoal #1C1C1E + amber #E8A87C
- SF Pro font (system default)
- 16px rounded corners

## Tech Stack
- SwiftUI + MapKit for UI
- Privy iOS SDK for auth (Sign in with Apple/Google/Email + embedded wallet)
- Supabase Swift SDK for backend (DB + Storage)
- Claude API (Anthropic Swift) for AI parsing
- Google Places API for place matching
- App Clip target for shareable trip links
- Share Extension target for cross-app saving

## Key Features to Stub
1. **Map View** — MapKit with custom annotations, category-colored pins, clustering, bottom sheet on tap
2. **List View** — Filterable (Want to Go/Visited/All + categories), sortable (Nearest/Recent/Rating), swipe to mark visited
3. **Trip Planner** — City selector, timeline view, drag-to-reorder, "Optimize Route" button (Google Maps Directions API for waypoint optimization + Claude for smart scheduling based on opening hours)
4. **Share Extension** — Accept URLs + images from any app, show AI parsing result, save to map
5. **Profile** — Stats (saved/visited/cities), world map visualization, collections, subscription management
6. **Onboarding** — 3-step carousel
7. **Place Detail** — Photo carousel, info, notes, navigate button, source link
8. **App Clip** — Lightweight version that opens shared trip links

## Dependencies (Swift Package Manager)
- privy-io/privy-ios
- supabase/supabase-swift  
- For Google Places: use REST API directly (URLSession)
- For Claude API: use REST API directly (URLSession)

## Data Model
```swift
struct Place: Identifiable, Codable {
    let id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var googlePlaceId: String?
    var category: PlaceCategory
    var status: PlaceStatus  // wantToGo, visited
    var rating: Double?
    var note: String?
    var sourceUrl: String?
    var sourcePlatform: SourcePlatform
    var sourceImageUrl: String?
    var extractedDishes: [String]?
    var priceRange: String?
    var recommender: String?
    var googleRating: Double?
    var googlePriceLevel: Int?
    var openingHours: String?
    var createdAt: Date
}

enum PlaceCategory: String, Codable, CaseIterable {
    case food, cafe, bar, attraction, stay, shopping
}

enum PlaceStatus: String, Codable {
    case wantToGo, visited
}

enum SourcePlatform: String, Codable {
    case instagram, threads, xiaohongshu, googleMaps, other
}
```

## Important
- This is a SCAFFOLD — stub all views with placeholder UI matching the design theme
- All services should have protocol + stub implementation
- Include proper .gitignore for Xcode/Swift
- Include README with setup instructions
- Do NOT include actual API keys
- Make sure it compiles (even if with placeholder data)
- Push to remote: https://github.com/JhiNResH/wanderly (force push OK, it's a fresh start)

When completely finished, run this command to notify me:
openclaw system event --text "Done: Wanderly iOS Swift project scaffolded with Privy + App Clip + Share Extension. Pushed to github.com/JhiNResH/wanderly" --mode now

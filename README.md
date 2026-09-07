# Savvy

Savvy is a private place-memory app for iOS. It turns travel and food clues into user-confirmed **Map Stamps**, with evidence receipts and trip planning from saved places.

```text
Source clue → Review candidate → user confirmation → Map Stamp → Plan
```

## Start here

| I want to… | Read |
|---|---|
| Understand the app and its boundaries | [Product overview](docs/product-overview.md) |
| Set up a local checkout | [Setup](docs/setup.md) |
| Build or run focused checks | [Verification](docs/verification.md) |
| Work on design or product states | [Design contract](DESIGN.md) |
| Configure share links and App Clips | [Sharing](docs/sharing.md) |
| Prepare a signed release or TestFlight upload | [Release guide](docs/releasing.md) |
| Find runbooks and historical records | [Documentation index](docs/README.md) |
| Find a proposal, spec, or verification receipt | [Specification index](specs/README.md) |

## Repository map

| Area | Purpose |
|---|---|
| [SAV-E/](SAV-E/) | SwiftUI app: views, models, services, and App Intents |
| [SAV-EShared/](SAV-EShared/) | Parsers and configuration shared by native targets |
| [SAV-EShareExtension/](SAV-EShareExtension/) | Capture URLs and text from other apps |
| [SAV-EClip/](SAV-EClip/) | App Clip share previews |
| [SAV-EiMessage/](SAV-EiMessage/) | Parked iMessage extension spike |
| [backend/](backend/README.md) | TypeScript API, Postgres schema, and backend tests |
| [save-rn/](save-rn/) | Expo web fallback for share, referral, and list routes |
| [services/evidence-rubric/](services/evidence-rubric/README.md) | Source-evidence evaluation service |
| [supabase/](supabase/) | Supabase migrations and Edge Function implementation |
| [Tests/](Tests/) · [fixtures/](fixtures/) | Native and CI tests; shared regression fixtures |
| [scripts/](scripts/) | Build, configuration, release, and verification helpers |
| [docs/](docs/README.md) | Maintainer guides, runbooks, security reviews, and history |
| [specs/](specs/README.md) | Product proposals, contracts, and evidence records |
| [design-assets/](design-assets/) | Design studies, brand assets, and App Store artwork |
| [Prototypes/AtlasPostcard/](Prototypes/AtlasPostcard/README.md) | Atlas prototype, design decisions, and CI visual-parity assets |

## Project entry points

- [project.yml](project.yml) owns XcodeGen targets and build numbers; [SAV-E.xcodeproj](SAV-E.xcodeproj/) is generated from it. Use the **SAV-E** scheme.
- [Package.swift](Package.swift) defines the Swift package and its dependencies.
- [vercel.json](vercel.json) configures the web fallback build and routing.
- [AGENTS.md](AGENTS.md) defines contribution, verification, and approval boundaries.
- [DESIGN.md](DESIGN.md) owns design intent and state language; [Color+Theme.swift](SAV-E/Extensions/Color+Theme.swift) owns palette values.

The installed app name is **Savvy**. Existing `SAV-E` paths and `com.wanderly.*` identifiers remain compatibility names. Release history is indexed in [docs](docs/README.md); build numbers and historical uploads do not establish current tester availability or public release.

## License

Private — All rights reserved.

# Savvy Design System

> Current main app direction: map-first Savvy. Earlier main-app designs are archived in [Legacy design history](SAV-E/Legacy/DESIGN.md). The [App Clip contract](DESIGN-CLIP.md) applies to that separate target only.

## Current product and root

Savvy turns saved-place clues into user-confirmed place memory. A clue, a Review Candidate and a confirmed Map Stamp must remain distinguishable within five seconds.

`SaveApp` owns onboarding, authentication and account verification. After verification the main root is `SavvyMainMapRoot`, using the real production persistence and handoff bindings. The map is the primary surface with three destinations: Saved, Map (globe icon), and Passport. Search and Add remain map actions. Friends and SAV-E Guide are reachable within this structure; never invent friend endorsements or location sharing. Preserve the glowing switch-like tab selection and a mounted map across tab changes. Do not deliver a separate City Lab app. The existing main app identity remains `com.wanderly.app`.

The accepted direction follows the supplied Anywhere references: a full-screen navigable map, round photo pins with responsive pop motion, rounded floating controls, clear hierarchy and adaptive day/night surfaces. Doodle paper, rough outlines and notebook styling are retired for new main surfaces. Existing account/settings compatibility routes retain their behavior until individually restyled; this is an explicit unfinished visual boundary, not fidelity approval.

Use [the region blueprint](Prototypes/CityMVP/REGION-BLUEPRINT.md) for each new district. Taipei uses Apple MapKit with the authored Xinyi scene; Shanghai requests Amap and remains explicitly unavailable until its key and SDK are connected. Apple controls MapKit's regional data providers. An Amap attribution within Apple Maps does not identify an Amap SDK integration.

The main root is not a fixture flag. Normal launches read the authenticated account's saved-place sources. Only explicit screenshot/suite launches may seed sample identities, shops, visits or friends.

## Requested public discovery default — 2026-11-14

The founder clarified that the default Map should reveal other people's public Instagram, Threads and Xiaohongshu posts associated with real places, without requiring the viewer to import those posts first. The local planning-preview code now defaults to Explore, retaining Mine and Friends. Installed phone152 remains the earlier personal-map baseline. Preserve Saved / Map / Passport and the separate personal/friends capabilities.

Discovery pins represent attributed public posts or grouped posts for a place, not the viewer's saved Map Stamps. Eligible source covers are labeled as post imagery; venue/business photography remains separate. A venue opens the associated posts, their authors/platforms and original links; explicit collection and Guide actions remain separate from browsing. Require a reliable place association before showing a geographical pin. Discovery must preserve original-source attribution and withdrawal/access boundaries.

The local preview's Plan with friends action opens an explicit shared-list chooser. Revalidate access and source expiry, add only a venue candidate to the chosen editable list, and never infer a personal save, visit, recommendation or post publication. Uncertain list writes permit read-only reconciliation, not automatic resubmission. Only verified presence enables a separate Open Guide action; it rereads that list in Friends for stop selection and planning rather than starting a route automatically.

The existing follower-only shared-post feed is not public discovery. A public-link capability alone is not permission to list a record globally. Current opt-in trending signals are aggregated Savvy place signals, not a global social-post index. A separate read-only operator index now supplies a validated post/author/source contract to the local preview; unset, invalid or expired data remains visibly unavailable. External platform acquisition and real coverage remain unimplemented; do not label fixtures, friend shares or search candidates as everybody's public posts. This change does not authorize publicizing existing private records, production migrations/deployment, credentials or spending. Public-source acquisition must work before presenting this local interface as a working live default on the phone.

## App icon alignment in the planning preview

The founder requested that the new personal/shared-map phone preview match the actual coral-and-cream Savvy icon. `SaveBrandUI` in `Color+Theme.swift` owns this preview's adaptive palette: warm off-white surfaces, coral accents, warm charcoal text and dark surfaces. `DateTheme` aliases those values only in the main Debug preview. Existing production and 3D palettes are preserved until separately integrated.

Keep clean, rounded cards and native readable typography. The brush wordmark belongs to branding; do not turn body text into handwriting or restore dotted paper, notebook decorations or rough borders. Saved, Map, Passport, search, place cards and compact account/edit/language/privacy routes share the palette. Retain the glowing three-tab selection, using the icon's coral accent. Photos must identify the actual business from a permitted source; source screenshots are not business photos and missing photos keep a category fallback. Opening a pin retains click-triggered pop/wobble with a stable bottom geographic anchor and Reduce Motion support. Map movement does not replay the click effect. Venue detail retains Savvy's icon-aligned palette, map/address and compact actions, with available Apple place metadata and eligible business/associated-website imagery. Apple's complete native card is a secondary information sheet. Show source links instead of generated or expanded note text; preserve original notes in storage and the canonical saved-place editor. New explicitly linked imports write only their source URL to note; post prose belongs to source evidence, never user-authored memory. Do not reinterpret Unplaced recovery or unclassified manual text as a new link import. Friend map pins show actual shared-post authors and their own marked-visited/shared status; sharing or rating is not an explicit recommendation.

## Visual authority

- `Color+Theme.swift` owns the shared palette; `CityMVPStyle` and `CityMVPFormStyle` currently own the integrated map and neutral surface tokens. Their historical names do not imply a separate app.
- Use adaptive cool surfaces, rounded system typography and readable contrast. No dotted paper or rough edges in new map/Saved/Passport surfaces. Day/night changes both chrome and authored scene lighting.
- Names, user comments, notes and source content stay in their original language. Translate app-owned copy only, including errors/status and accessibility labels.
- Confirmed saves, review candidates and unresolved clues have distinct symbols and text, never just different colors. Pins use stable geographic anchors; decorative scale/pop must not move the anchor.

## Branding, entry and loading

Use the Savvy brush lettering from the supplied app icon. The current entry direction has no large banner, elephant/Memo illustration or decorative Atlas ticket stack. Preserve the supplied lettering's stroke design and readable contrast on the actual background. A logo is branding, never a confirmed place or verified-visit stamp.

The sign-in/loading redesign owns its entry components and brand assets. Keep actual sign-in, verification-code, waiting, retry, keyboard and account-recovery states distinct. Do not simulate analysis progress, imply authenticated content before the account gate passes, or publish fixture success as real authentication.

## Language

Language controls must preserve Follow iOS, English and 繁體中文 behavior. Existing account settings remain a compatibility route until their visual update is verified.

Offer Follow iOS, English and 繁體中文. A fresh preference follows the ordered supported iOS language preferences; manual choices persist and can return to Follow iOS. Update the visible interface immediately, refresh on activation/locale changes, and keep SwiftUI locale consistent. A system option must not present the current manual choice as the iOS result.

## Saved places, Passport and identity

Earlier name-only Ink saves and full visit metadata remain available through the owner-filtered, read-only Place history sheet. Do not invent UUIDs, save dates or coordinates to coerce them into native map records; do not erase their original stores.

Passport is the account's place archive and control surface. It exposes confirmed saved places even when they have no visit record; a saved place opens its detail without adding a visit or stamp.

- Clues retain their source and uncertainty. They are not saved Map Stamps. Source-only clues without reliable coordinates do not become map pins.
- Review Candidates are possible matches and need the existing explicit confirmation before becoming user truth.
- The branded collection keeps a separate To review section for current pending clues. A capture batch filters only this section and can return to all pending clues; confirmed-place counts and saved-status filters never absorb or hide pending clues. Opening a row resolves its current ID before presenting the canonical review. Exact-place correction uses a visible search sheet and returns to it after an unconfirmed result is closed.
- Map Stamps are confirmed saved places. Saved/unvisited, visited, location-verified visits and unverified visits remain separate, explicitly labeled states.
- Never turn a self-marked or legacy Visited status into verified arrival, receipt/photo proof, purchase or physical-delivery evidence.
- Normal Passport identity comes from the authenticated account and its account-scoped local avatar. It never displays a fixture name/city as the user. A backend canonical profile ID may differ from its Privy subject; freshness belongs to the requested owner/session.
- An unavailable profile is shown as unavailable with retry. Opening Passport must not reset Privy, rewrite saved memories, recover pending deletion cleanup or migrate avatar files implicitly. Older legacy-only photos need their own supported recovery path.
- Account changes invalidate previous identity, places, delayed requests and private drafts. User notes remain unchanged even when their text equals a generated fallback label.

## Maps and visits

The main world and Taipei map use Apple MapKit. Authored 3D appears only within its sourced district envelope, with continuous camera/pin ownership, thinning cloud transition and no duplicate ground. Distances and walking time must come from actual location/route calculations; do not substitute illustrative times. Test fixtures stay isolated from real account records.

Arrival verification remains a one-shot explicit action under the existing permission, precision, distance and freshness rules. Unlocated places may record an unverified visit through the explicit unverified action. No background tracking or coordinates are written into visit records by this UI.

A private visit/comment stays out of friends' content and public counts. Saving or visiting a place does not publish it. Sharing, attachments and withdrawal retain their explicit consent and audience boundaries; attribution and original private notes must not leak through a recipient save.

## Existing commercial and handoff boundaries

This design cleanup does not change entitlement, account, import or payment behavior. Preserve the existing 50-place cap and its pending/Unplaced recovery. “You've saved 50 places. Keep going.” remains informational until the configured purchase route is available. Display localized StoreKit product prices, never a hardcoded $6.99. Keep `SAVEPro.storekit` verification intact. `ai.quotaExhausted` remains a retry/error state and does not itself open the places paywall.

Share Extension and App Clip retain their existing journaling and full-app confirmation contracts. Sign-in or closing a preview never confirms a save. The separate Clip contract is active; it must not become the main app's visual style.

## Accessibility and verification

- Tappable controls have at least 44 pt targets and cover their full visible row, including empty space. Icon actions have localized labels.
- Long English and Chinese text, Dynamic Type, keyboard and small-height layouts preserve core actions. Allow wrapping and scrolling; do not hide overflow with clipping.
- State never relies on color alone. Use readable text/symbols and preserve contrast.
- Keep current screenshot fixtures isolated from real accounts and saved records. A synthetic screenshot is layout evidence, not live data recovery or physical production evidence.
- The fourteen Ink baselines in `Prototypes/AtlasPostcard/Reference/InkNotebook/` remain pending founder approval. Preserve those files and their frozen hashes.
- `ProductionTargets/map.png` from `a5d62df8` remains the approved map visual reference. Existing 0.90 visual gates, unmasked evidence, supplemental lanes and all unit/UI coverage remain required; archival does not waive them.
- Compile membership, account/data safety and current Ink UI must all be verified after source moves. An unchanged archived source body does not by itself prove that a new screen avoids it.

## Archive boundary

`SAV-E/Legacy/{App,Views}` holds earlier main-app screens, and `Prototypes/AtlasPostcard/Legacy/Sources` holds earlier prototype code. They remain compiled only for existing types, compatibility routes and regression coverage. Reference images, fonts and required evidence remain in their established locations. Archival does not delete features, account data or tests.

Historical Atlas/Doodle/TileTown layout tests read the archived design document. New main-app work reads this current contract. If a compatibility route still needs an archived view, name that boundary explicitly; do not copy its appearance into the Ink root. The active onboarding/auth source remains with its separate redesign owner until integration.

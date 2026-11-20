# Savvy Design System

> Current main app: Ink notebook. Earlier main-app designs are archived in [Legacy design history](SAV-E/Legacy/DESIGN.md). The [App Clip contract](DESIGN-CLIP.md) applies to that separate target only.

## Current product and root

Savvy turns saved-place clues into user-confirmed place memory. A clue, a Review Candidate and a confirmed Map Stamp must remain distinguishable within five seconds.

`SaveApp` owns onboarding, authentication and account verification. After verification the shipping root is `SaveInkNotebookRoot`: one home, no tab bar. Its current screens and chrome live in `SAV-E/Views/InkNotebook/`. Do not restore the five-tab shell, TileTown, Atlas, Doodle or cream-notebook settings styles by reusing archived views.

The current Ink root is not a fixture flag. Normal launches read the authenticated account's saved-place sources. Only explicit screenshot/suite launches may seed sample identities, shops, visits or friends.

## Requested public discovery default — 2026-11-14

The founder clarified that the default Map should reveal other people's public Instagram, Threads and Xiaohongshu posts associated with real places, without requiring the viewer to import those posts first. The local planning-preview code now defaults to Explore, retaining Mine and Friends. Installed phone152 remains the earlier personal-map baseline. Preserve Saved / Map / Passport and the separate personal/friends capabilities.

Discovery pins represent attributed public posts or grouped posts for a place, not the viewer's saved Map Stamps. Eligible source covers are labeled as post imagery; venue/business photography remains separate. A venue opens the associated posts, their authors/platforms and original links; explicit collection and Guide actions remain separate from browsing. Require a reliable place association before showing a geographical pin. Discovery must preserve original-source attribution and withdrawal/access boundaries.

The local preview's Plan with friends action opens an explicit shared-list chooser. Revalidate access and source expiry, add only a venue candidate to the chosen editable list, and never infer a personal save, visit, recommendation or post publication. Uncertain list writes permit read-only reconciliation, not automatic resubmission. Only verified presence enables a separate Open Guide action; it rereads that list in Friends for stop selection and planning rather than starting a route automatically.

The existing follower-only shared-post feed is not public discovery. A public-link capability alone is not permission to list a record globally. Current opt-in trending signals are aggregated Savvy place signals, not a global social-post index. The native preview implements the validated post/author/source contract. Explore shows unavailable while the read-only operator index endpoint is deferred. External platform acquisition and real coverage remain unimplemented; do not label fixtures, friend shares or search candidates as everybody's public posts. This change does not authorize publicizing existing private records, production migrations/deployment, credentials or spending. Public-source acquisition must work before presenting this local interface as a working live default on the phone.

## App icon alignment in the planning preview

The founder requested that the new personal/shared-map phone preview match the actual coral-and-cream Savvy icon. `SaveBrandUI` in `Color+Theme.swift` owns this preview's adaptive palette: warm off-white surfaces, coral accents, warm charcoal text and dark surfaces. `DateTheme` aliases those values only in the main Debug preview. Existing production and 3D palettes are preserved until separately integrated.

Keep clean, rounded cards and native readable typography. The brush wordmark belongs to branding; do not turn body text into handwriting or restore dotted paper, notebook decorations or rough borders. Saved, Map, Passport, search, place cards and compact account/edit/language/privacy routes share the palette. Retain the glowing three-tab selection, using the icon's coral accent. Photos must identify the actual business from a permitted source; source screenshots are not business photos and missing photos keep a category fallback. Opening a pin retains click-triggered pop/wobble with a stable bottom geographic anchor and Reduce Motion support. Map movement does not replay the click effect. Venue detail retains Savvy's icon-aligned palette, map/address and compact actions, with available Apple place metadata and eligible business/associated-website imagery. Apple's complete native card is a secondary information sheet. Show source links instead of generated or expanded note text; preserve original notes in storage and the canonical saved-place editor. New explicitly linked imports write only their source URL to note; post prose belongs to source evidence, never user-authored memory. Do not reinterpret Unplaced recovery or unclassified manual text as a new link import. Friend map pins show actual shared-post authors and their own marked-visited/shared status; sharing or rating is not an explicit recommendation.

## Visual authority

- Main Ink palette, Iansui type and rough shape geometry are owned by `SaveInkPalette`, `SaveInkType` and the primitives in `SAV-E/Views/InkNotebook/SaveInkNotebookChrome.swift`. Use those existing values; do not approximate them with legacy theme names or copy a second palette into a new view.
- The canvas is Ink paper; text and outlines use Ink ink or muted ink. Controls use the same rough circles and rounded rectangles as Home, place detail and the save sheet.
- Iansui applies to the main notebook's headings, body and control labels. Preserve Dynamic Type scaling. A new control must not silently switch to Atlas system-font cards, dotted paper or colored selection badges.
- Ordinary control selection is monochrome and has a shape/text state. The arrival action is the main UI accent. Brand artwork has its own supplied colors and must remain legible.
- Names, user comments, notes and source content stay in their original language. Translate app-owned copy only, including error/status text and accessibility labels.

Shared `Color+Theme.swift` definitions remain for compatibility and separate consumers; their presence does not authorize using a retired main-app style. New color decisions need a scoped design decision and matching source changes.

## Branding, entry and loading

Use the Savvy brush lettering from the supplied app icon. The current entry direction has no large banner, elephant/Memo illustration or decorative Atlas ticket stack. Preserve the supplied lettering's stroke design and readable contrast on the actual background. A logo is branding, never a confirmed place or verified-visit stamp.

The sign-in/loading redesign owns its entry components and brand assets. Keep actual sign-in, verification-code, waiting, retry, keyboard and account-recovery states distinct. Do not simulate analysis progress, imply authenticated content before the account gate passes, or publish fixture success as real authentication.

## Language

Welcome and Passport use `SaveInkLanguageSheet`, with Ink paper, Iansui, rough outlines, a monochrome selected radio and a complete tappable row. They must not instantiate the archived language/settings sheet.

Offer Follow iOS, English and 繁體中文. A fresh preference follows the ordered supported iOS language preferences; manual choices persist and can return to Follow iOS. Update the visible interface immediately, refresh on activation/locale changes, and keep SwiftUI locale consistent. A system option must not present the current manual choice as the iOS result.

## Saved places, Passport and identity

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

Normal Ink Home and place detail use Apple MapKit with the existing Ink pins, muted map emphasis and light paper overlay. Distances and walking time come from the current location/MapKit path. Fixture and screenshot launches keep the isolated drawn map.

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

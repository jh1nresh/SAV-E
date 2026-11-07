# Savvy Design System

> Current main app: Ink notebook. Earlier main-app designs are archived in [Legacy design history](SAV-E/Legacy/DESIGN.md). The [App Clip contract](DESIGN-CLIP.md) applies to that separate target only.

## Current product and root

Savvy turns saved-place clues into user-confirmed place memory. A clue, a Review Candidate and a confirmed Map Stamp must remain distinguishable within five seconds.

`SaveApp` owns onboarding, authentication and account verification. After verification the shipping root is `SaveInkNotebookRoot`: one home, no tab bar. Its current screens and chrome live in `SAV-E/Views/InkNotebook/`. Do not restore the five-tab shell, TileTown, Atlas, Doodle or cream-notebook settings styles by reusing archived views.

The current Ink root is not a fixture flag. Normal launches read the authenticated account's saved-place sources. Only explicit screenshot/suite launches may seed sample identities, shops, visits or friends.

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
- Map Stamps are confirmed saved places. Saved/unvisited, visited, location-verified visits and unverified visits remain separate, explicitly labeled states.
- Never turn a self-marked or legacy Visited status into verified arrival, receipt/photo proof, purchase or physical-delivery evidence.
- Normal Passport identity comes from the authenticated account and its account-scoped local avatar. It never displays a fixture name/city as the user. A backend canonical profile ID may differ from its Privy subject; freshness belongs to the requested owner/session.
- An unavailable profile is shown as unavailable with retry. Opening Passport must not reset Privy, rewrite saved memories, recover pending deletion cleanup or migrate avatar files implicitly. Older legacy-only photos need their own supported recovery path.
- Account changes invalidate previous identity, places, delayed requests and private drafts. User notes remain unchanged even when their text equals a generated fallback label.

## Maps and visits

Home is the saved-place list and has no inline map. Place detail maps follow the viewed destination's country, not the viewer's location or language: mainland China (`CN`) uses the official interactive Amap web map without an SDK key; Hong Kong, Macau, Taiwan and other countries use Apple MapKit. Only WGS84 references enter MapKit, walking routes and one-shot arrival measurement; provider GCJ-02 references remain typed and are displayed by Amap without rewriting stored coordinates. Country lookup is read-only and transient; destination administrative metadata separates Taiwan, Hong Kong and Macau from aggregate country responses. Ambiguous Kinmen/Matsu metadata stays unavailable. WGS84 mainland points use the official coordinate-aware marker request only to resolve a strictly validated official HTTP redirect tied to the original navigation, then display the compact GCJ-02 embed; converted display coordinates are never saved. This redirect response shape is an integration dependency, so unknown shapes fail closed. Unresolved country/provider data and failed network maps (including an HTML shell without map tiles after a single 25-second render deadline) show an unavailable state with retry or the trusted provider handoff, never a mislabeled map. The embedded map receives destination data only, uses ephemeral web storage, disables its normal geolocation API, and cannot navigate arbitrary links. Fixture and screenshot launches keep the isolated drawn map on place detail.

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

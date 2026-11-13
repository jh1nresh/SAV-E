# Guide and friends: accepted product direction

Decision recorded on 2026-11-11 from the user's instructions. This is product
intent, not a claim that the preview implements these features.

2026-11-12 functional update: the local candidate now implements explicitly
selected recommendation-file exchange, source-aware saved-place Guide details,
address actions, Apple system translation presentation and venue-only exports
for a local read-only MCP server. See [function completion](FUNCTIONAL-WORK.md)
and [MCP setup](MCP/README.md). Native verification is tracked separately; these
changes do not establish a live friend network, a model-backed Guide, automatic
post reading, external AI-client acceptance or authenticated Shanghai rendering.

## Primary job

Help foreign visitors explore mainland Chinese cities like they have a local
friend. Visitors may not read Chinese or understand Xiaohongshu guides. SAV-E
should help them understand a post or screenshot, identify the correct branch,
choose a place, and get there with useful local guidance.

## Friends, sharing, and choosing

Friends' recommendations are a core input to the guide, not a separate generic
review feed. The user explicitly wants to use recommendations from people they
trust. Apply the travel-agent network idea to this flow:

1. A friend chooses which recommendations, lists, and visit notes to share.
2. The visitor chooses whose recommendations to view and which places interest
   them. The map can show friend avatars and circular place-photo pins.
3. SAV-E explains who recommended a place and why, then helps choose using the
   visitor's present needs and available local information.
4. Chosen places can become a route or plan. A choice does not create a Map
   Stamp until the user confirms the place.

Keep these statements distinct: a friend explicitly recommends a place; a
friend saved it but has not visited; a friend has visited; an agent infers a
match. Agents must not invent an endorsement or treat a visit as a positive
recommendation. Show the source and relevant date. Sharing must use the
friend's permitted information, not their private history or live location.

## Agent responsibilities

- A friend's agent can provide that friend's authorized recommendations and
  experiences. A working first version may use directly shared lists instead
  of requiring every friend to have an agent.
- SAV-E Guide Agent combines those inputs with Chinese-language source material
  and verified place details. It helps with translation, branch identity,
  practical cautions, directions, ordering, and communicating an address.
- Make source content, current verified facts, friend experience, and agent
  inference distinguishable. Public sources can supplement missing friend
  recommendations without being presented as friend recommendations.
- MCP is the intended connection to other AI clients and agents. It is not
  implemented merely because the preview includes an agent entry point.

## Scope and application

Apply this direction to the map's Friends entry, place cards, sharing and
selection flows, and the Guide Agent. Main navigation remains Saved, Map,
Passport; the map is the primary surface. Do not invent friends or social
activity to fill the preview.

For non-map surfaces, use the user's Ramin Nasibov reference
(https://x.com/RaminNasibov/status/2120151222065692729) for layout, rounded
controls, avatars, and card hierarchy. Keep the Anywhere reference for the map,
photo pins, and zoom experience. Preserve the existing three-tab dock's moving
glass lens, continuous icon magnification, spring settling, and blue-white glow
when applying the non-map direction. Do not replace that transition with static
tab swaps. Respect Reduce Motion and Reduce Transparency.

Group preference coordination can follow this loop. Supplier offers,
negotiations, bookings, and payments are later work and require separate
product decisions and authority.

The local agent entry searches confirmed saves and opens their Guide brief.
It does not yet read Xiaohongshu links, contact friends' agents, verify current
business details, or run a model. An explicitly exported venue can be queried
through the separate read-only MCP stdio adapter; that is not live account sync.

## Reference observed and bounded preview application

The UI maker inspected the actual public Ramin post in Chrome on 2026-11-11:
https://x.com/RaminNasibov/status/2120151222065692729 . The public post calls it
an app concept for finding a fair meeting spot for friends. Browser screenshots
showed the `Friday crew` heading, `Tonight, 8:00 PM · 6 going`, compact
`Vote / Middle / Spot` pills, a pale map with circular face markers, white
fades around the map, softly rounded comparison rows, and a place detail card
with one dominant bottom action. These are visual reference observations, not
Savvy users, places, ratings, travel times, attendance, or sharing evidence.
The review should compare hierarchy and spacing against this source; this is
an adaptation, not an exact reproduction of every frame or animation.

The prototype applies a neutral system background, quiet gray cards, system
text, compact stage pills and rounded action grids to Saved, Passport,
Capture, Search, Friends and the local Guide sheet. The map, photo pins,
selected-place map panel, zoom and glowing moving navigation lens keep their
separate Anywhere direction. All colors adapt to system appearance; neutral
form helpers do not change global map or dock tokens.

Current functional boundaries:

- Saved uses confirmed local places and a real empty-state Add action. Needs
  review remains a separate entry, never a confirmed-save count.
- Capture's Link, Photo, Nearby and File actions still use the existing draft,
  native paste, image OCR, search and import paths. `Clue / Review / Save` is a
  description of the existing confirmation sequence; Find the place creates
  Review Candidates, not Map Stamps.
- Search's category tiles call the existing category filters on saved places.
  They are labeled as saved-place filters, not live restaurant suggestions.
  Submitted map results remain explicitly not saved.
- Friends opens a local recommendation-file exchange from Map or Passport.
  Senders select venues and write sharing-specific text; recipients preview,
  select and explicitly confirm their own saves. Labels are self-declared and
  copies are forwardable/non-revocable. Notes, photos, ratings, visited state
  and sender attribution are not inherited into recipient Place memory.
  This does not create profiles, read private histories, share live locations,
  send invitations or verify who authored a file.
- Guide searches confirmed local saves, then shows original address, source
  statements, private note and saved date separately. Copy/address-card/map
  actions are local. A driver card needs a street number. Apple translation
  opens only on a user's action; language availability remains a runtime gate.
  Venue-only JSON export excludes private memory. The separate MCP server
  performs real read-only protocol calls against that export, with no model,
  live account, source browsing or mutation. Registry/traces/mock R8/SLR
  contracts still do not establish real Guide execution.
- Passport retains HTTPS-only source access for the selected place, geographic
  attribution, original photo links, authors, licenses and modification notes.
  Account, authentication, identity, purchase and visit semantics are unchanged.

Source parsing and instruction consistency can be checked in this scope;
rendered appearance, tap routing, small-height layouts and keyboard behavior
require the controller's serialized build and runtime evidence. The UI maker
is not the independent reviewer of this change.


## Original local functional slice specification

The brief/detail/export portion below is now implemented in the local candidate.
The following paragraphs retain its scope; runtime results live in the function
completion receipt, and unresolved hosted/agent boundaries remain open.

Build a source-aware brief from an existing confirmed local Place. This is a
useful guide input before real model execution, not a substitute claim that an
LLM or MCP is connected. The existing search path remains
Sources/CityMVPAgentSheet.swift -> Sources/CityMVPAgentMemory.swift.

Future allowlist: new Sources/CityMVPGuideBrief.swift and
Tests/CityMVPGuideBriefTests.swift, plus Sources/CityMVPAgentSheet.swift only.
Use Place.userFacingNote and Place.durableStructuredEvidence from
../../SAV-E/Models/Place.swift. Keep original name and address, saved date,
user notes and source statements distinct. The saved date is not a verification
date. Missing address/source/note has an explicit absence state. Only safe HTTPS
source URLs can open. Copy address and Show on map use existing local actions
and onOpen; use the existing MapKit-mappable coordinate boundary. Do not
translate, infer current facts, write places, mark visits, invent people or
execute any network call. Tests cover absent/unsafe source, empty notes,
separate source/user text, original Chinese text, non-WGS84 routing and
candidate exclusion. Runtime must prove open/copy/back/map and unchanged saves.

Existing friend-list structures are not endorsement evidence:
../../SAV-E/Models/SaveCollaborativeList.swift contains SaveListItem and
join(from:), but an author label is not a verified friend identity. Shared post
models in ../../SAV-E/Models/SharedPlacePost.swift include revocation boundaries;
the hosted endpoints in ../../SAV-E/Services/SupabaseService.swift have not been
verified in this local task. Define the explicit recommendation action and
what survives revocation before connecting a real friend-recommendation feed.
A save or visit alone is not permission to publish a recommendation.

../../backend/src/server.ts stores validated tool-call traces; that does not
execute an agent. ../../specs/agent-callable-memory-contract.md explicitly
identifies seeded R8/SLR capabilities as mocks. A working model/provider, tool
execution and actual MCP client exchange require separate end-to-end evidence.

2026-11-13: Guide now has an explicit local Friends’ picks retrieval mode. Venue/sender/reason matching keeps source identity separate, and native verification proves exact-source removal updates results without changing the saved-place vault. This still is copied-source retrieval, not live identity or a generated AI conversation. Evidence: `PreviewEvidence/guide-retrieval-20261113/RESULT.md`.

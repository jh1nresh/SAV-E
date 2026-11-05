# Savvy App Clip Design

This is the active, separate App Clip target contract. Its visuals do not define the main Ink notebook. Source-owned Clip catalog values and all existing handoff, privacy and verification gates remain authoritative.


DESIGN **v3.1 (plan A)** supersedes v1/v2. The Clip is a full-page shared
place (or a vertically paged list of place pages). It does not show a map,
preview card, tab bar, or footnote. Google Places photos do not appear on
any Clip screen. Shared and public payloads contain no Google-domain URLs
(photos or source links). Trip / referral / My Savvy stay functional and
are not restyled here.

### Flow

The approved flow is **pending in the Clip → full App sign-in → explicit
confirmation → saved place**. This supersedes the v3.1 standalone Clip save
and Apple-to-Privy carry-over behavior. An Apple identifier is never a Privy
session or a saved-place owner.

A place or “Save all N” action first writes its selected snapshot to App Group
`pendingShare` (`group.com.wanderly.app`). Nothing becomes a Map Stamp at this
tap. If installed, open the full App with the matching link. Otherwise show
“Ready to confirm in Savvy” with the selected count and an install action;
`SKOverlay(AppClipConfiguration(position: .bottom))` is presented only after
that install action and successful journaling. Failed journaling shows Retry,
never pending success. Failed app opening retains the journal and offers retry.
The Clip performs no sign-in and no place mutation HTTP request.

The full App uses its normal authenticated account flow. It shows the selected
place receipt, or an explicit list of selected places, and requires a fresh
“Confirm save” tap before writing. Closing the preview or signing in does not
confirm a save. A failed request retains the journal and offers retry with
confirmation. A newer pending invocation needs its own confirmation. Session
changes cancel stale writes; sign-out/account switch clears the prior account's
handoff. First login preserves an unowned pending journal.

The full App shows success only after the backend confirms the save. Existing
places count once and the existing full-App free-cap handling applies. On a cap
refusal, preserve the pending journal and the current Unplaced/paywall recovery;
a partial backend result is not reported as a completed handoff. A confirmed
success clears only the unchanged matching journal, never a replacement.

### Place page

Full screen. Top hero 393×470 pt (~55%) with a jittery torn-paper bottom
and a 1.6 pt ink line. Show only the sharer’s own public photo. The main
state is no photo: coral fill, cream jitter circle (236 pt), large
category sticker (restaurant = noodle bowl, cafe = coffee cup). Bowl/cup
plate fill is kraft `#EADDC6` in light and dark (`ClipStickerInk.plate`).
Outline is `ClipStickerInk` `#2F2E23` in both modes — never a black oval
or `#000000`. Plate, bowl, and cup strokes are 1.6 pt; cup handle 2.4 pt;
chopsticks 2.0 pt. If no sticker fits, a cream line-art pin. No Temple of
Heaven, roast duck, or elephant.

Over the hero: left is the sharer chip (short-code + backend sender only)
— cream capsule (`#FFF9EB` both modes), `ClipStickerInk` text and jitter
border (`#2F2E23` both modes) so `{name} shared with you` / `{name} 分享給你`
stays readable in dark. System 14 semibold. Right is the Savvy wordmark
on a small cream plate (Caveat, no elephant).

Place name is handwriting: Caveat 38 (en) / Iansui 34 (zh), max 2 lines.
`Area · Category` is system 15 muted. Friend note is a zigzag washi strip
at −1.2°, system 16 (`publicNote`, max 180), attribution system 12.

One primary button: coral capsule height 54, ink jitter border, cream
system 17 semibold. Then a coral-underline “Open in Apple Maps” (system
15 semibold). Hide it, or fall back to an address search, when there are
no coordinates.

### List

One place page per page. Vertical paging
(`ScrollView` + `.scrollTargetBehavior(.paging)`). Right-side vertical
page indicator. Over the hero: sharer chip and, under it, the list
title (handwritten, cream) plus `第{i}/{n}家` / `{i} of {n}`. Swipe
hint 「往上滑看下一家」 / "Swipe up for the next place" on page 1
only (SL6). After the first swipe, persist `clipListSwipeHintDismissed`
in App Group `group.com.wanderly.app` and never show it again. Each
page's primary button selects **that** place only for confirmation in the
full App. A secondary button, “Continue with N places” /「帶 N 家到 Savvy」,
selects the whole list. Both journal a deduplicated snapshot in list order;
the full App must not substitute a subsequently changed live list. It sends
the selected places only after its explicit confirmation. Free-cap overflow
keeps the journal pending and uses the existing full-App Unplaced/paywall path.
Legacy v3.1 LS4, saved state 19 and partial state 19b are superseded by the
pending screen; sign-in and actual save outcomes belong to the full App.
Reduce Motion is respected. The App Group remains `group.com.wanderly.app`,
not `group.com.wanderly.app.shared`.

### Tokens (V3.1)

The Clip target cannot link the main app. Catalog colors in
`SAV-EClip/Assets.xcassets` are the Clip source. **Coral stays `#F26B4A`
in light and dark** (`ClipCoral`) — it does not follow the main-app dark
`#D97861`.

| Role | Clip catalog | Light | Dark |
| --- | --- | --- | --- |
| Canvas / paper | `ClipCanvas` | `#FFF9EB` | `#1E1C17` |
| Card | `ClipCard` | `#FFF9EB` | `#2A2721` |
| Ink | `ClipInk` | `#2F2E23` | `#FFF9EB` |
| Muted | `ClipMuted` | `#62594F` | `#BDB3A2` |
| Line | `ClipLine` | `#DCCFB9` | `#4A443A` |
| Kraft | `ClipKraft` | `#EADDC6` | `#3A342A` |
| Coral (CTA, hero) | `ClipCoral` | `#F26B4A` | `#F26B4A` |
| Forest / wordmark | `ClipForest` | `#0E4A33` | `#B9E0C9` |
| Cream / button label | `ClipCream` | `#FFF9EB` | `#FFF9EB` |
| Sticker / chip ink | `ClipStickerInk` | `#2F2E23` | `#2F2E23` |
| Sticker plate | `ClipStickerInk.plate` | `#EADDC6` | `#EADDC6` |

No shadows, gradients, or blur. No MapKit on place or list pages. No
elephant. Unmatched hero categories use the cream line-art pin.

### Type

Handwriting (Caveat Latin / Iansui zh-Hant) only for the place name, list
title, and state titles. Everything else is the system font. Wordmark is
Caveat “Savvy” at a fixed 34 pt in `ClipForest` on a cream plate. Ship
`Iansui-ClipTitles.ttf`. Do not copy `Iansui-SavvySubset.ttf` (3.48 MB).
Missing Iansui glyphs cascade to Caveat for Latin shop names, then the
system font. Proof: `SAV-E/Resources/DisplayFont/11-iansui-proof.md`.

### Size

Uncompressed per-variant budget is **15 MB** until the Clip
deployment-target / physical-invocation question is settled (Z1). Ship
only the Clip catalog, Caveat, the Clip Iansui title subset, and vector
stickers drawn in SwiftUI.

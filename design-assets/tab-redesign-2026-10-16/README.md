# Four-tab reference implementation

The founder supplied Home, Map, Friends and Passport references on 2026-10-16,
reviewed a unified four-screen concept, then authorized native implementation
based on PR #279. This is presentation work; existing data, privacy, capture,
review, search, sharing and secondary routes remain in place.

## Artwork provenance

Both assets were generated with the built-in image tool on 2026-10-16 from that
concept. They are fictional, decorative illustrations, not business photographs,
geographic tiles, visit evidence or user avatars.

- `SavvyTownArtwork.imageset/artwork.png`: scenery only. Native SwiftUI renders
  every interactive pin, label, search field, selected-place ticket and action.
- `SavvyStampArtwork.imageset/artwork.png`: six equal squares in a 3×2 atlas:
  harbor, pine, maple / mountain, lake, cafe. Runtime cropping is explicit and
  cached. Real available place photos retain precedence; these illustrations
  are the offline/category fallback. Follower photos retain the existing
  authenticated, memory-only loading path.

The original procedural town remains a missing-asset fallback. This explicitly
updates the previous renderer-only lock to use the selected detailed art; it
does not restore a live MapKit basemap or imply real-world coordinates.

### 2026-10-17 polish assets

Generated with the built-in image tool for the founder's four-item polish request:

- `SavvyCategoryStampArtwork.imageset/artwork.png`: 3×2 atlas, bar / hotel /
  restaurant / noodle shop / book-and-flower shop / cottage. Generic decorative
  category art, not photos or likenesses of named businesses. Existing place
  category chooses the illustration; original nature scenes remain available.
- `SavvyFriendPortraits.imageset/artwork.png`: 3×2 atlas of fictional pixel
  travelers. A stable author-ID hash chooses a fallback; real avatar URLs take
  precedence. No appearance is inferred and no generated avatar is persisted
  or published to a profile.

Both atlases are bundled originals (1536×1024); SwiftUI uses cached equal-cell
cropping and nearest-neighbor display. They add no external runtime provider.

## Acceptance and verification

- Atlas palette, native body text, mixed-case pixel display, clipped kraft
  controls, perforated collection stamps and flat five-control navigation.
- Home town/selected memory, waiting clues and recent stamps stay distinct.
- Map keeps native lenses, pan, selected-place action and search drawer.
- Friends keeps live author/post actions and explicit shared/want-to-go copy.
- Passport opens saved places, initially shows six slots, can expand the full
  collection, and retains identity/settings/quests/shared posts below.
- No new auth, payment, backend, persistence or publication behavior.

Verification: Swift syntax parsing and diff checks locally; generic build,
all SAVETests, full UI integration, 0.90 visual parity and legacy Trip sheet
coverage on CI. The existing screenshot rail now captures populated Friends
and Passport and checks the progress track and stamp-to-detail action.
Local Xcode/runtime is skipped due to storage pressure (~13 GiB before work);
no local simulator or DerivedData is created. Current-head independent review
is required before readiness. Merge and release remain human-controlled.

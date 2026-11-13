# Savvy region rollout blueprint

The delivery target for this rollout is the main Savvy app, `com.wanderly.app`.
The existing `CityMVP` directory supplies reusable map code and assets; its
standalone City Lab target is historical verification infrastructure, not this
task's delivered product. This blueprint records the region contract. Build,
same-version runtime, review, CI, merge and release remain separate evidence.

## Shared product and visual contract

- Keep the same three tabs and their jobs across regions. A new city supplies
  map configuration and reviewed content; it does not create a different shell.
- Use the rollout's neutral map chrome and existing day/night materials. Region
  configuration owns no new palette, typography, tab, account or storage system.
- Keep existing photo-pin selection, dimensions, source licensing and saved/visit
  distinctions. An illustrative context POI is not a confirmed Map Stamp. Source
  clues and Review Candidates need explicit confirmation before becoming saved
  user truth. A renderer or region change never saves or verifies a visit.
- Preserve native continuous pan, pinch, rotate and camera ownership. Authored
  geometry follows the same registered camera; cloud handoff follows native
  distance and existing scene-readiness rules. A new region must not swap in an
  unrelated orbit camera, freeze pins, or reveal a complete scene on a timer.
- Preserve the current Xinyi geometry, facade/material treatment, lighting,
  context labels and ground/cloud seams. Catalog metadata is not a replacement
  renderer. No copied Xinyi buildings may stand in for an unbuilt city.

The checked-in `DESIGN.md` still describes the earlier Ink root with no tab bar.
The three-tab map rollout is a scoped product change and needs its controller's
design-contract update; this document does not silently redefine unrelated Ink
or App Clip behavior. Palette authority remains the actual source tokens.

## Typed region contract

`Sources/SavvyMapRegion.swift` is a small catalog and routing helper. It does not
fetch places, decide user truth, change stored coordinates, or authenticate SDKs.

| ID | Requested renderer | Initial camera | Authored coverage |
| --- | --- | --- | --- |
| `world` | Apple Maps / MapKit | Existing world camera | None |
| `taipei-xinyi` | Apple Maps / MapKit | Existing Xinyi overview | Existing 101–City Hall source envelope |
| `shanghai` | Amap SDK | Pending; no invented camera | None; connection and model alignment pending |

Use `region(for:)` to resolve a stable ID and `selection(for:amapStatus:)` to
choose Apple Maps or the existing Amap pending state. All current Amap statuses
remain pending, including a present key with `sdkNotConnected`. Missing SDK
credentials must remain visible; selecting Shanghai is not connection evidence.
Apple Maps remains usable when Amap is unavailable.

The requested renderer is separate from the regional data provider chosen by
MapKit. `appleDataProviderPolicy == .selectedByMapKit` makes no assertion about
which vendor a particular device receives. Seeing regional provider attribution
inside Apple Maps is not proof that this app has an authenticated Amap SDK.

## Coordinates, geometry and provenance

- Xinyi authored geometry uses the existing WGS84 source origin
  `(25.033968, 121.564468)` with east `x` and south `z` in meters. Reuse
  `CityDistrictCamera.coordinate/world`; do not introduce a second conversion.
- `AuthoredCoverage.bounds` describes the source envelope, not verified current
  buildings: `x = -700...700`, `z = -568...700`. The opaque ground core is
  `x = -550...550`, `z = -518...550`. These bounds derive from the renderer's
  existing constants, including its limited northern extract and feather.
- Apply `CityDistrictRegistration` at the MapKit boundary using the verified
  public landmark result. Camera, geometry and bundled pin anchors share that
  registration. Never bake a device/provider offset into saved user coordinates
  or reuse a fixture offset as normal startup truth.
- Amap integration needs its independently verified GCJ-02 anchor and explicit
  source-to-provider conversion contract. Keep the original coordinate system
  identified; avoid double conversion and never relabel WGS84 as GCJ-02.
  Shanghai currently has neither a connected SDK nor accepted authored coverage.
- Preserve provenance for each extract, footprint, height, handcrafted landmark,
  facade, sign, texture and photo. The bundled Taipei OSM extract is credited in
  `README.md` and `Resources/taipei-osm.json` under ODbL; photo licenses and crop
  disclosures live in `Resources/PhotoCredits.txt`. Code licensing does not
  replace asset licensing. Existing geometry/store names are illustrative;
  reviewed shape is not verified reality, business status or entrance accuracy.

## Checklist for the next region

1. Add one stable region ID/profile with requested renderer and a reviewed camera.
   Keep authored coverage absent until actual assets and alignment are reviewed.
   A pending region needs a clear unavailable state and a usable return path.
2. Record source coordinate system, anchor, bounds, provenance, asset licenses,
   footprint/height assumptions and materials. Distinguish sourced measurements,
   authored approximations and founder-reviewed appearance from verified reality.
3. Verify provider terms, target-specific SDK availability and bundle entitlement.
   Credentials are a separate authorized setup action. A key's presence alone
   must not transition the profile to connected or fabricate a successful map.
4. Reuse the three-tab shell and account-scoped data. Preserve clue / Review
   Candidate / Map Stamp distinctions and photo-pin state rules across regions.
5. Freeze deterministic fixtures for catalog routing, missing/mismatched keys,
   camera numerics, source bounds and coordinate registration. Test that another
   region cannot accidentally use Xinyi's geometry. Keep fixtures free of private
   account data and production credentials.
6. Run the main `SAV-E` generic simulator build and `SAVETests`, then required CI
   and independent review on the same head. Runtime acceptance must use the same
   main-app version: continuous camera, pin contact/selection, cloud seam, pan
   beyond coverage, day/night, interruption and Reduce Motion. Screenshots alone
   do not verify continuous gesture behavior or provider connectivity.

`Tests/SocialPlacePipelineTests/SavvyMapRegionTests.swift` freezes current world
and Xinyi camera numerics, source/opaque bounds, unique IDs and pending Amap
routing using synthetic configuration states. Main-target compile membership,
runtime acceptance and SDK credentials remain the controller's explicit gates.

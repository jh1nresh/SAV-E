# Savvy City Lab: Xinyi preview

An independent local iOS app for exploring the Taipei 101–City Hall corridor
and two detailed intersections beside Taipei 101. It uses a separate app identifier and local vault. A screenshot,
an unsaved map pin, and a confirmed Map Stamp remain different states; only
the explicit save action writes a Map Stamp. This target is for local
design review and is not added to the shipping Xcode project.

Choose **Taipei** and pinch into the district. The 3D scene follows the
Apple Maps camera and dissolves back to the basemap when zooming out. Geometry
is assembled in cooperative batches and installed only after resource preparation;
the native map remains available in the meantime. A failed preparation exposes
an explicit Retry action. Landmark alignment also has a ten-second deadline and a manual Retry control; a missing lookup never substitutes guessed coordinates. Leaving and returning to the district reuses the scene
while this map screen remains mounted. Use
**Explore** to jump to the City Hall Road and Songzhi Road intersections.
The two blocks include illustrative storefronts, sidewalk and road details,
and simulated cars. The northern corridor includes City Hall, public squares,
planted parks and raised retail walkways based on the bundled public footprints. The original 101 model has eight flared, chamfered tiers and a stepped crown; camera containment reads those same profiles. Roof trim and bounded rooftop equipment follow eligible building footprints and avoid the tower shaft. Traffic is animated only at close zoom, while the app
is active and Reduce Motion is off. Taipei 101 and ATT 4 FUN have distinct
photo pins. Thin photo rims and compact labels distinguish ordinary context
pins from the cyan selected badge; only a saved place receives a bookmark. The Shanghai row is a configuration placeholder; no Amap SDK
is connected.

## Current verification

The 2026-11-11 candidate passes the generic arm64 iOS Simulator test build.
Source-derived desktop checks cover the district geometry, sampled camera/pin
projection, cloud clearing, day/night palette, navigation dock and place card.
These checks do not establish current physical-device gesture continuity, frame
rate, contextual-pin overlap or whole-app similarity to Anywhere. The earlier
iOS runtime results apply to their recorded older builds. A fresh phone
installation and runtime check remain separate gates. GitHub Actions stays disabled.

## Run locally

Use an Apple silicon Mac with Xcode, XcodeGen, Python 3 and PyYAML. Verified
with Xcode 27.2 and an iOS 26.5 simulator. Run from the repository root:

```sh
python3 Prototypes/CityMVP/run-bounded.py bash Prototypes/CityMVP/build-local.sh
xcrun simctl list devices available
```

Choose a shutdown simulator from that list. The runtime check requires
at least 10 GiB free at startup.

```sh
export SAVVY_CITY_MVP_DEVICE='<simulator-udid>'
python3 Prototypes/CityMVP/runtime-local.py --xinyi-only
```

The verifier takes an exclusive lock on its simulator and build cache. It
builds and runs the hosted and focused UI tests, then launches the app for
inspection. From another shell, request closeout with
`touch Prototypes/CityMVP/runtime-stop.local`. The verifier shuts down its
simulator and releases its locks. It does not delete the simulator or cache.

## Assets

[The Taipei extract](Resources/taipei-osm.json) is ©
[OpenStreetMap contributors](https://www.openstreetmap.org/copyright) and is
distributed under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
The asset has its own license, separate from the app code. Scene geometry and
store names are illustrative and do not represent current conditions.
See [photo credits](Resources/PhotoCredits.txt) for image sources, licenses
and crop disclosures.

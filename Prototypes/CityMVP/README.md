# Savvy City Lab: Xinyi preview

An independent iOS simulator app for exploring two intersections beside
Taipei 101. It uses a separate app identifier and local vault. A screenshot,
an unsaved map pin, and a confirmed Map Stamp remain different states; only
the explicit save action writes a Map Stamp. This target is for local
design review and is not added to the shipping Xcode project.

Choose **Taipei** and pinch into the district. The 3D scene follows the
Apple Maps camera and dissolves back to the basemap when zooming out. Use
**Explore** to jump to the City Hall Road and Songzhi Road intersections.
The two blocks include illustrative storefronts, sidewalk and road details,
and simulated cars. Traffic is animated only at close zoom, while the app
is active and Reduce Motion is off. Taipei 101 and ATT 4 FUN have distinct
photo pins. The Shanghai row is a configuration placeholder; no Amap SDK
is connected.

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

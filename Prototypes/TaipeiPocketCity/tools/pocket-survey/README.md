# Original Pocket City paint on the continuous globe

This delivery continues PR #466 (and its #456–#465 predecessors). It keeps the 200m street scene, current walking routes, surveyed building geometry and authored landmark meshes. The atlas is original Pocket City paint; windows, window spacing and colors are illustrative. There is no store/floor truth inferred from these windows, and browsing does not create saved Map Stamps.

The map retains user rotation and pitch through zoom and delayed catalog loads. Desktop offers pointer/keyboard camera controls. The native host retains its own chrome and65-degree camera persistence limit; web allows75degrees. Camera gestures stay enabled on both.

## Source and reproducibility

`kit/source.json.gz` preserves all six original Pocket City module texts byte for byte; `kit/LICENSE.txt` retains the MIT notice. `input.json` contains the public source palette and an empty camera context. Install the pinned dependency with `npm ci --ignore-scripts`, then run `node build-facades.cjs` to reproduce the12-slot PNG and manifest.

To reproduce classification from the frozen source scene collection:

```
uv run --with numpy --with shapely python classify-facades.py --scenes /path/to/frozen/taipei/work/scenes
python -B verify.py
```

Prepare the repo's measured geometry with `python -B ../../prepare_data.py` if `data/` has not been restored. The frozen source collection contains7047 `.json.gz` scenes; its aggregate SHA256 and all source mesh/payload hashes are in `facade-classification.json`. Raw scene inputs are authoring data, not bundled into the app.

Class0 is generic illustrative paint. Class1 requires mapped residential evidence; class2 requires explicit glass/mirror material; class3 preserves mapped school, religious or landmark material. Up to three largest interior triangle centroids must each have nonempty agreeing source evidence. Partial/absent/conflicting evidence stays generic. Mesh coordinates, actual height, base and courtyard holes are unchanged. Source fragments and mesh groups are not unique building counts.

Class buffers load alongside geometry without blocking it. They are validated for length, enum and per-triangle consistency. Stale, invalid or unavailable class data falls back to generic class0 paint; unavailable atlas paint retains the pre-refinement surface. The5 native package checks verify that the atlas, all4816 class files and camera stylesheet are included and authoring sources remain excluded.

## Verified and pending

The preceding local pass checked all7047 cell IDs and source/terrain receipts and all4816 mesh identities. It rendered Yongchun in matched before/after cameras plus101, Songyan and Qixing, and tested returning to the globe. This integration keeps the source geometry and submitted original paint; native device rendering still needs verification. Local Node suite with `POCKET_TAIPEI_DATA` set covers all311 tests, including retained landmark geometry and three new gesture/disposal checks.

This is a general facade refinement, not7047 individually researched final scenes. Official2026 MOI20m DTM/schema downloads remain HTTP403; the user has no copy. Terrain remains the existing Mapzen-derived DEM; its vertical datum alignment has not been verified. Individual landmark/nature work and tree grounding/occlusion remain pending. Local source receipts are not proof of every rendered seam.

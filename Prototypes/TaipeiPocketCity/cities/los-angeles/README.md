# Los Angeles · Griffith Observatory

Open `index.html` from disk to rotate, zoom, and change the weather. This 250 m square includes Griffith Observatory, its front lawn, and the Astronomers’ Monument.

## Rebuild

Run from this directory with Python 3.9+, Shapely, and the Pocket City skill installed.

```bash
kit="${POCKET_CITY_SKILL:-$HOME/.codex/skills/pocket-city}/scripts"
python3 "$kit/plot.py" --osm osm-bbox.json --rotate north --keep 'Griffith Observatory' --out plot.json
python3 "$kit/prep.py" --osm osm-bbox.json --plot plot.json --drive right --out scene.json
python3 refine-scene.py
python3 "$kit/build.py" --scene scene.json --city city.json --landmarks landmarks.js --out index.html
```

`osm-bbox.json` contains tagged objects from the official OpenStreetMap bounding-box API with the way coordinates resolved from the same response. `metadata.json` lists the original request and reference sources. The ground is flat in the model. Planting is illustrative, with tree scatter limited to keep the Observatory’s real lawns and terraces open.

"""Build and verify Pocket City street scenes registered in cities/catalog.json."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
from city_catalog import PLACES, catalog as make_catalog
import sys
import tempfile
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1] / "cities"


def read(path):
    return json.loads(path.read_text())


def check(value, message):
    if not value:
        raise ValueError(message)


def block(html, name):
    match = re.search(r'<script\b[^>]*\bid="' + name + r'"[^>]*>(.*?)</script>', html, re.S)
    check(match, f"Missing {name} in the built page")
    return match[1].strip()


def verify(folder, page):
    meta, plot, scene = (read(folder / filename) for filename in ("metadata.json", "plot.json", "scene.json"))
    geo = scene["meta"]
    check(len(meta["center"]) == 2 and all(abs(a - b) < .000002 for a, b in
          zip(meta["center"], (geo["lon"], geo["lat"]))), "Scene and metadata centers differ")
    check(geo["size"] == meta["sizeMeters"] == plot["size"] and geo["size"] > 0, "Conflicting plot sizes")
    check(all(abs(geo[k] - plot[k]) < 1e-6 for k in ("lon", "lat", "rotation")), "Inconsistent plot transform")
    check(not plot["famous_cut"] and not plot["keep_missing"], "A protected landmark crosses or misses the plot")
    rad = math.radians(geo["rotation"])
    lx = 111320 * math.cos(math.radians(geo["lat"]))
    corners = [(geo["lon"] + (x*math.cos(rad) - y*math.sin(rad))/lx,
                geo["lat"] + (x*math.sin(rad) + y*math.cos(rad))/110574) for x, y in scene["corners"]]
    xs, ys = zip(*corners)
    check(len(meta["bounds"]) == 4 and all(abs(a-b) < .000015 for a, b in zip(
          meta["bounds"], (min(xs), min(ys), max(xs), max(ys)))), "Map bounds do not enclose the rotated artwork")
    buildings = {row["id"]: row for row in scene["buildings"]}
    ids = meta["landmarkIds"]
    sites=meta.get('landmarkSites', [])
    check((ids or sites) and all(key in buildings and not buildings[key].get("cut") for key in ids),
          "Primary landmark missing or clipped")
    if sites:
        raw = read(folder/"osm.json")["elements"]
        for site in sites:
            source = next((r for r in raw if r['type']==site['osmType'] and r['id']==site['osmId']), None)
            check(source and source['tags']['name']==site['name'], "Unverified landmark site")
            w,s,e,n=meta["bounds"]
            points=source.get("geometry") or [source]
            check(all(w<=p["lon"]<=e and s<=p["lat"]<=n for p in points), "Site crosses the drawing bounds")
            check(w<=site['point'][0]<=e and s<=site['point'][1]<=n,"Site pin outside drawing")
    sources = meta["sources"]
    check(sources and all(s["title"] and urlsplit(s["url"]).scheme in {"http", "https"} for s in sources),
          "Missing landmark references")
    html = page.read_text()
    check(json.loads(block(html, "sceneMeta")) == {k: geo[k] for k in
          ("lat", "lon", "size", "rotation", "osm_base")}, "Stale embedded georeference")
    check(json.loads(block(html, "cityData")) == read(folder / "city.json"), "Stale embedded city configuration")
    scene_text = "const SCENE=" + json.dumps(scene, ensure_ascii=False, separators=(",", ":")) + ";"
    check(block(html, "data").startswith(scene_text.replace("</script", "<\\/script")), "Stale embedded scene")
    artwork = (folder / "landmarks.js").read_text().strip()
    check(artwork and artwork.replace("</script", "<\\/script") == block(html, "landmarks"), "Stale landmark artwork")
    if page.parent==folder:
        raw=(folder/'map-mesh.bin').read_bytes()
        parts=read(folder/'map-mesh.json')['parts']
        count=0
        for part in parts:
            check(part['first']==count and part['count']>0 and part['count']%3==0 and
                  len(part['at'])==2 and all(math.isfinite(v) for v in part['at']),"Invalid mesh part")
            count+=part['count']
        check(count>0 and len(raw)==count*16, "Invalid mesh byte length")
        check(all(all(math.isfinite(v) for v in vertex[:3]) and vertex[-1]==255
                  for vertex in struct.iter_unpack('<fff4B',raw)),"Invalid mesh vertex")
    print(f"{folder.name}: {geo['size']:g} m, {len(ids)} primary footprints, {len(buildings)} mapped building records")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("build", "verify"))
    parser.add_argument("city", nargs="?", help="catalog id; defaults to all in published order")
    parser.add_argument("--skill-dir", default=os.environ.get("POCKET_CITY_SKILL"))
    args = parser.parse_args()
    catalog = read(ROOT / "catalog.json")
    if args.action=="verify" and not args.city:
        check({r["id"] for r in catalog}==set(PLACES), "Missing required city pack")
        check(catalog==make_catalog(), "Rebuild the viewport index with tools/city_catalog.py")
    ids = [row["id"] for row in catalog]
    check(ids and len(ids) == len(set(ids)) and all(re.fullmatch(r"[a-z0-9-]+", key) for key in ids),
          "Invalid catalog IDs")
    if args.city and (not re.fullmatch(r"[a-z0-9-]+",args.city) or not (ROOT/args.city/"metadata.json").exists()):
        parser.error("Unknown city")
    if args.action == "build" and not args.skill_dir:
        parser.error("Provide the Pocket City skill path using --skill-dir or POCKET_CITY_SKILL")
    for city in [args.city] if args.city else ids:
        folder = ROOT / city
        page = folder / "index.html"
        if args.action == "verify":
            verify(folder, page)
            continue
        with tempfile.TemporaryDirectory(dir=folder) as temporary:
            output = Path(temporary) / "index.html"
            subprocess.run([sys.executable, str(Path(args.skill_dir) / "scripts/build.py"),
                            "--scene", str(folder/"scene.json"), "--city", str(folder/"city.json"),
                            "--landmarks", str(folder/"landmarks.js"), "--out", str(output)], check=True)
            output.write_text("\n".join(line.rstrip() for line in output.read_text().splitlines()).rstrip()+"\n")
            verify(folder, output)
            os.replace(output, page)
            subprocess.run(["node",str(ROOT.parent/"tools/export-pocket-mesh.mjs"),str(page)],check=True)
            verify(folder,page)


if __name__ == "__main__":
    main()

"""Audit Taipei's complete 170 m atlas against its restored public-data corpus.

Requires Shapely 2, pyproj, numpy, Pillow and ijson. The receipts count source features
and geographical availability; they do not assert that every feature is visible at once.
"""

import argparse
import gzip
import hashlib
import json
import math
import subprocess
from array import array
from collections import Counter, defaultdict
from pathlib import Path

import ijson
import numpy as np
import shapely as geo
from PIL import Image
from pyproj import Transformer
from shapely.geometry import LineString, Polygon, box, shape
from shapely.ops import polygonize, unary_union

TO_METRES = Transformer.from_crs(4326, 3826, always_xy=True)
SIZE = 170


def load(path):
    with gzip.open(path, "rt") if path.suffix == ".gz" else path.open() as f:
        return json.load(f)


class Audit:
    def __init__(self, data):
        self.data = data
        self.index = load(data / "city170/index.json")
        self.fail = Counter()
        self.examples = defaultdict(list)
        self.outside = Counter()
        self.totals = Counter()
        self.detail = {}
        self.rows = []
        self.by_id = {}
        grid = load(data / "city170/grid.json.gz")["features"]
        polys = []
        for i, f in enumerate(grid):
            p = f["properties"]
            self.require(p["id"] == f["id"] and p["id"] not in self.by_id, "grid-id", p["id"])
            self.by_id[p["id"]] = i
            polys.append(shape(f["geometry"]))
            self.rows.append(
                {
                    "id": p["id"],
                    "pack": p["pack"],
                    "districts": p["districts"],
                    "center": p["center"],
                    "counts": Counter(),
                }
            )
        self.g = np.array(polys, dtype=object)
        self.tree = geo.STRtree(self.g)
        self.m = geo.transform(self.g, TO_METRES.transform, interleaved=False)
        districts = load(data / "districts.geojson")["features"]
        district_geom = geo.make_valid(
            geo.transform(
                np.array([shape(f["geometry"]) for f in districts]), TO_METRES.transform, interleaved=False
            )
        )
        self.district_names = [f["properties"]["name"] for f in districts]
        official = geo.union_all(district_geom)
        actual = geo.union_all(self.m)
        missing = geo.area(geo.difference(official, actual))
        excess = geo.area(geo.difference(actual, official))
        self.detail["gridGeometry"] = {
            "crs": "EPSG:3826",
            "missingM2AfterCoordinateRounding": round(missing, 3),
            "excessM2AfterCoordinateRounding": round(excess, 3),
        }
        self.require(
            self.index["crs"] == "EPSG:3826" and self.index["cellSize"] == SIZE, "grid-crs", "index"
        )
        dtree = geo.STRtree(district_geom)
        for i, r in enumerate(self.rows):
            a, b = map(int, r["id"].split("_"))
            expected = f"p{a // 8}_{b // 8}"
            area = self.m[i].area
            r["areaM2"] = round(area, 3)
            r["edge"] = area < SIZE**2 - 1
            self.require(
                area > 0
                and self.m[i]
                .difference(box(a * SIZE, b * SIZE, (a + 1) * SIZE, (b + 1) * SIZE).buffer(0.02))
                .area
                < 0.01,
                "grid-square",
                r["id"],
            )
            self.require(expected == r["pack"], "grid-pack", r["id"])
            actual_d = set()
            for j in dtree.query(self.m[i]):
                if district_geom[j].intersection(self.m[i]).area > 1:
                    actual_d.add(self.district_names[j])
            self.require(actual_d.issubset(r["districts"]), "district-coverage", r["id"])
        self.expected_kinds = Counter(self.index["stats"]["byKind"])
        self.owners = {}
        self.primary_kinds = {}
        self.direct = {}
        self.school_ids = set()
        self.frontage_ids = set()

    def require(self, condition, issue, item):
        if condition:
            return
        self.fail[issue] += 1
        if len(self.examples[issue]) < 10:
            self.examples[issue].append(str(item))

    def geometries(self, points, key, weights=None):
        if len(points) == 0:
            return
        src, dest = self.tree.query(points, predicate="intersects")
        for j, i in zip(src, dest):
            self.rows[i]["counts"][key] += 1 if weights is None else weights[j]
        self.outside[key] += len(points) - len(np.unique(src))

    def xy(self, coords, key):
        if coords:
            pts = np.array(coords, dtype=float)
            self.geometries(geo.points(pts[:, 0], pts[:, 1]), key)

    def global_features(self, path, kind):
        groups = defaultdict(list)
        for f in load(path)["features"]:
            groups[kind(f)].append(shape(f["geometry"]))
        for k, v in groups.items():
            self.geometries(v, k)
            self.totals[k] += len(v)

    def drawing_inputs(self):
        # Execute the JS shipped in this exact capsule. Reflect the layer filter instead of
        # maintaining a second list of bridge, tunnel, indoor and covered stair exceptions.
        script = r"""
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
const {courtMarkings}=await import('./city170-courts.js');
const {surfaceFeature}=await import('./city170-ground.js');
const {addCity170Style}=await import('./city170-style.js');
const {supplements:recoveredFronts}=await import('./taipei-frontage-pack.js');
let filter;
const ctx=new Proxy({}, {get:()=>()=>({addColorStop(){}})});
globalThis.document={createElement:()=>({getContext:()=>ctx})};
const map={getStyle:()=>({layers:[]}),getSource:()=>null,getLayer:()=>null,hasImage:()=>true,addImage(){},
  addLayer(l){if(l.id==='city170-stair-treads')filter=l.filter;}};
addCity170Style(map,'features');
if(!filter)throw Error('Stair layer missing');
function evaluate(expr,p){
  if(!Array.isArray(expr))return expr;
  const [op,...a]=expr,run=value=>evaluate(value,p);
  switch(op){
  case 'literal':return a[0]; case 'get':return p[a[0]];
  case 'all':return a.every(run); case 'any':return a.some(run);
  case '==':return run(a[0])===run(a[1]); case '!=':return run(a[0])!==run(a[1]);
  case 'coalesce':return a.map(run).find(v=>v!==null&&v!==undefined);
  case 'to-number':return a.map(run).map(Number).find(Number.isFinite);
  case 'in':return run(a[1]).includes(run(a[0])); default:throw Error('Unsupported '+op);
  }
}
const ids={courts:[],treads:[],recoveredFronts};
const index=JSON.parse(readFileSync('data/city170/index.json'));
for(const row of index.packs){
  const pack=JSON.parse(gunzipSync(readFileSync('data/city170/'+row.url)));
  for(const raw of pack.features.features){
    const f=surfaceFeature(raw);
    if(!f)continue;
    if(f.properties.kind==='pitch'&&courtMarkings(f))ids.courts.push(f.id);
    if(f.properties.category==='steps'&&evaluate(filter,f.properties))ids.treads.push(f.id);
  }
}
console.log(JSON.stringify(ids));
"""
        return json.loads(
            subprocess.check_output(
                ["node", "--input-type=module", "-e", script], cwd=self.data.parent, text=True
            )
        )

    def packs(self):
        root = self.data
        features_by_kind = Counter()
        found = set()
        memberships = Counter()
        paths = {}
        objs = {}
        sport = Counter()
        categories = Counter()
        supplemental = {}
        draw = self.drawing_inputs()
        courts = set(draw["courts"])
        stairs = set(draw["treads"])
        open_ground = load(root / "city170-open-ground.json.gz")
        self.detail["drawingEligibility"] = {
            "singleCourtMarkings": len(courts),
            "groundStairTreads": len(stairs),
            "recoveredFronts": len(draw["recoveredFronts"]),
        }
        schools = load(root / "city170/schools.json.gz")["features"]
        self.school_ids = {f["id"] for f in schools if f["properties"]["kind"] == "school"}
        self.global_features(
            root / "city170/schools.json.gz",
            lambda f: "schoolArea" if f["properties"]["kind"] == "school" else "schoolLabel",
        )
        front_summary = load(root / "city170-frontages/summary.json")
        self.detail["frontages"] = {
            k: front_summary[k] for k in ["input", "matched", "skipped", "searchCount", "skipReasons"]
        }
        self.detail["packInventorySHA256"] = {}
        for folder, pattern in [
            ("city170", "p*.json.gz"),
            ("city170-life", "p*.json.gz"),
            ("city170-nature", "p*.json.gz"),
            ("city170-frontages", "p*.json.gz"),
            ("city170-prepared", "*.json.gz"),
        ]:
            have = {
                ("p" if folder == "city170-prepared" else "") + p.name[:-8]
                for p in (root / folder).glob(pattern)
            }
            digest = hashlib.sha256()
            for asset in sorted((root / folder).glob(pattern)):
                digest.update(asset.name.encode() + b"\0")
                with asset.open("rb") as handle:
                    digest.update(hashlib.file_digest(handle, "sha256").digest())
            self.detail["packInventorySHA256"][folder] = digest.hexdigest()
            expected = {p["id"] for p in self.index["packs"]}
            for k in sorted(have ^ expected):
                self.require(False, folder + "-inventory", k)
        for pack in self.index["packs"]:
            k = pack["id"]
            pkg = load(root / "city170" / pack["url"])
            prepared = load(root / "city170-prepared" / (k[1:] + ".json.gz"))
            feats = pkg["features"]["features"]
            self.require(pkg["id"] == k and len(feats) == pack["counts"]["features"], "pack-payload", k)
            refs = 0
            deps = set()
            for c in pkg["cells"]:
                cid = c["id"]
                self.require(cid not in found and cid in self.by_id, "pack-cell-identity", cid)
                found.add(cid)
                i = self.by_id[cid]
                r = self.rows[i]
                self.require(
                    r["pack"] == k
                    and r["districts"] == c["districts"]
                    and r["center"] == c["center"]
                    and tuple(c["bounds"]) == tuple(self.g[i].bounds)
                    and self.g[i].equals_exact(shape(c["geometry"]), 0),
                    "pack-grid-disagreement",
                    cid,
                )
                memberships.update(c["districts"])
                r["dependencies"] = c["deps"]
                self.direct[cid] = c["refs"]
                refs += len(c["refs"])
                deps.update(c["deps"])
                self.require(len(set(c["refs"])) == len(c["refs"]), "duplicate-cell-ref", cid)
                self.require(cid in prepared, "missing-prepared-cell", cid)
                crowns = set()
                for f in prepared.get(cid, []):
                    kind = f["properties"]["kind"]
                    r["counts"]["prepared/" + kind] += 1
                    if kind == "grove-tree":
                        crowns.add(tuple(f["geometry"]["coordinates"]))
                excluded = {tuple(pt) for pt in open_ground.get(cid, [])}
                self.require(excluded <= crowns, "missing-open-ground-crown", cid)
                r["counts"]["openGroundCrownsRemoved"] = len(excluded)
                r["counts"]["groveCrownsAfterOpenGround"] = r["counts"]["prepared/grove-tree"] - len(
                    excluded
                )
            self.require(set(prepared) == {r["id"] for r in pkg["cells"]}, "prepared-pack-cells", k)
            self.require(
                len(pkg["cells"]) == pack["counts"]["cells"]
                and refs == pack["counts"]["refs"]
                and deps == set(pack["deps"]),
                "pack-manifest",
                k,
            )
            for f in feats:
                pid = f["id"]
                p = f["properties"]
                kind = p["kind"]
                category = p.get("category", "")
                self.require(pid not in self.owners, "duplicate-canonical-id", pid)
                self.owners[pid] = k
                self.primary_kinds[pid] = kind
                features_by_kind[kind] += 1
                extras = []
                if kind in ("road", "walk") and p.get("name"):
                    extras.append("namedStreet")
                if kind == "pitch":
                    sport[p.get("sport") or "unspecified"] += 1
                    if p.get("sport"):
                        extras.append("sportTagged")
                if kind in ("forest", "park", "pitch", "road", "walk"):
                    categories[kind + "/" + category] += 1
                if kind == "forest" and category in ("wetland", "scrub", "grassland"):
                    extras.append("habitat/" + category)
                if kind == "walk" and category == "steps":
                    extras.append("steps")
                    if pid in stairs:
                        extras.append("stepsEligibleForTreads")
                if pid in courts:
                    extras.append("singleCourtEligibleForLines")
                if p.get("vendor"):
                    extras.append("mappedVendor")
                if extras:
                    supplemental[pid] = extras
            life = load(root / "city170-life" / (k + ".json.gz"))
            for ident, path in life["paths"].items():
                if ident in paths:
                    self.require(paths[ident] == path, "conflicting-pedestrian-path", ident)
                else:
                    paths[ident] = path
            for ident, o in life["objects"].items():
                if ident in objs:
                    self.require(objs[ident] == o, "conflicting-scenery-object", ident)
                else:
                    objs[ident] = o
            self.xy([r[:2] for r in load(root / "city170-nature" / (k + ".json.gz"))], "inventoryTree")
            fronts = load(root / "city170-frontages" / (k + ".json.gz"))
            self.require(len(fronts) == front_summary["packs"][k], "frontage-pack-count", k)
            for f in fronts:
                self.require(f["id"] not in self.frontage_ids, "duplicate-frontage", f["id"])
                self.frontage_ids.add(f["id"])
                self.require(
                    (root / "200" / (f["surveyTile"] + ".bin.gz")).is_file(),
                    "frontage-missing-wall-mesh",
                    f["id"],
                )
            self.xy([r["center"] for r in fronts], "matchedFrontage")
        self.require(features_by_kind == self.expected_kinds, "canonical-kind-count", features_by_kind)
        self.require(
            found == self.by_id.keys() and len(self.rows) == self.index["stats"]["cells"],
            "grid-cardinality",
            len(found),
        )
        for d in self.index["districts"]:
            self.require(memberships[d["name"]] == d["cells"], "district-manifest-count", d["name"])
        self.require(
            open_ground.keys() <= found, "open-ground-unknown-cell", sorted(open_ground.keys() - found)[:5]
        )
        used = set()
        for r in self.rows:
            allow = {r["pack"], *r["dependencies"]}
            for ref in self.direct[r["id"]]:
                used.add(ref)
                self.require(self.owners.get(ref) in allow, "unresolved-ref", r["id"] + ":" + ref)
                if ref in self.primary_kinds:
                    r["counts"]["osm/" + self.primary_kinds[ref]] += 1
                r["counts"].update(supplemental.get(ref, ()))
        self.require(
            used == self.owners.keys(),
            "unreferenced-canonical-feature",
            sorted(self.owners.keys() - used)[:5],
        )
        self.require(
            {k for k, v in self.primary_kinds.items() if v == "school"} == self.school_ids,
            "school-source-identity",
            "schools.json.gz",
        )
        self.detail["canonicalUniqueCounts"] = dict(features_by_kind)
        self.detail["categoryInventory"] = dict(sorted(categories.items()))
        self.detail["pitchSports"] = dict(sorted(sport.items()))
        self.totals["pedestrianPaths"] = len(paths)
        self.geometries([LineString(p["points"]) for p in paths.values()], "pedestrianPath")
        for kind in sorted({o[2] for o in objs.values()}):
            self.xy([o[:2] for o in objs.values() if o[2] == kind], "object/" + str(kind))
        before = len(self.frontage_ids)
        for f in draw["recoveredFronts"]:
            self.require(
                f["id"] not in self.frontage_ids
                and (root / "200" / (f["surveyTile"] + ".bin.gz")).is_file(),
                "invalid-recovered-frontage",
                f["id"],
            )
            self.frontage_ids.add(f["id"])
        self.xy([f["center"] for f in draw["recoveredFronts"]], "recoveredMatchedFrontage")
        self.detail["frontages"]["afterRecovery"] = len(self.frontage_ids)
        self.detail["frontages"]["unmatchedAfterRecovery"] = front_summary["input"] - len(self.frontage_ids)
        self.require(before == front_summary["matched"], "matched-frontages-source", before)
        self.global_features(root / "city170-waterways.json.gz", lambda f: "streetWaterway")
        self.global_features(root / "city170-airfield.json.gz", lambda f: "publicTerminalApron")
        farm = root / "city170-farmland.json.gz"
        self.global_features(farm, lambda f: "streetFarmland")
        self.detail["drawingEligibility"]["farmlandAssetAvailable"] = farm.exists()
        search = load(root / "city170-frontages/search.json.gz")
        self.require(len(search) == front_summary["searchCount"], "store-search-count", len(search))
        self.require(
            self.frontage_ids.issubset({r[6] for r in search}),
            "frontage-missing-search-row",
            "search.json.gz",
        )
        self.xy([r[3:5] for r in search], "shopSearch")
        self.xy([r[3:5] for r in search if r[6] not in self.frontage_ids], "shopWithoutMatchedFacade")
        self.global_features(root / "city-place-index.json.gz", lambda f: "publicPlace")
        self.global_features(root / "city170-markets.json.gz", lambda f: "marketArea")
        self.global_features(root / "city170-landscape.json.gz", lambda f: "midZoomLandscape")
        for k in ["shops", "inspected-shops"]:
            self.global_features(root / ("city170-" + k + ".json.gz"), lambda f, k=k: "extraPOI/" + k)

    def verify_zero_refs(self):
        empty = [r for r in self.rows if not self.direct[r["id"]]]
        if not empty:
            return
        tree = geo.STRtree([self.g[self.by_id[r["id"]]] for r in empty])
        for pack in self.index["packs"]:
            features = load(self.data / "city170" / pack["url"])["features"]["features"]
            geometries = np.array([shape(f["geometry"]) for f in features], dtype=object)
            source, cell = tree.query(geometries, predicate="intersects")
            for j, i in zip(source, cell):
                self.require(
                    False, "unindexed-geometry-in-empty-cell", empty[i]["id"] + ":" + features[j]["id"]
                )

    def survey(self):
        # File shape and actual mesh vertices are tested separately. Bounding boxes alone
        # cannot show whether a sparse tile contains a building in a particular 170 m cell.
        sv = load(self.data / "survey-index.json")
        self.detail["surveyBuildings"] = sv["stats"]["buildings"]
        tiles = sv["levels"]["200"]
        ids = {t["id"] for t in tiles}
        for missing in ids ^ {p.name[:-7] for p in (self.data / "200").glob("*.bin.gz")}:
            self.require(False, "survey-200-files", missing)
        dx = np.array([int(r["id"].split("_")[0]) for r in self.rows])
        dy = np.array([int(r["id"].split("_")[1]) for r in self.rows])
        stride = dy.max() - dy.min() + 1
        index = np.full((dx.max() - dx.min() + 1) * stride, -1, dtype=int)
        index[(dx - dx.min()) * stride + dy - dy.min()] = np.arange(len(dx))
        for t in tiles:
            with gzip.open(self.data / "200" / (t["id"] + ".bin.gz"), "rb") as f:
                buf = f.read()
            self.require(len(buf) == t["verts"] * 24, "survey-byte-count", t["id"])
            v = np.frombuffer(buf, dtype="<f4").reshape(-1, 6)
            self.require(np.isfinite(v).all(), "nonfinite-survey-mesh", t["id"])
            xy = np.ascontiguousarray(v[:, :2]).view("<c8").ravel()
            unique = np.unique(xy)
            lon = (t["mx"] + unique.real.astype(float) * t["m"]) * 360 - 180
            lat = np.degrees(
                np.arctan(np.sinh(math.pi * (1 - 2 * (t["my"] - unique.imag.astype(float) * t["m"]))))
            )
            x, y = TO_METRES.transform(lon, lat)
            ix = np.floor(x / SIZE).astype(int) - dx.min()
            iy = np.floor(y / SIZE).astype(int) - dy.min()
            inside = (ix >= 0) & (iy >= 0) & (ix <= dx.max() - dx.min()) & (iy < stride)
            cardinal = np.full(len(ix), -1, dtype=int)
            cardinal[inside] = index[ix[inside] * stride + iy[inside]]
            for cell in np.unique(cardinal):
                if cell < 0:
                    continue
                r = self.rows[cell]
                if r["edge"]:
                    mask = cardinal == cell
                    if not geo.intersects_xy(self.g[cell], lon[mask], lat[mask]).any():
                        continue
                r["counts"]["surveyTilesWithVertices"] += 1
        self.detail["surveyFineTileCount"] = len(tiles)

    def nationwide(self):
        base = self.data.parent / "taiwan"
        for name, layer in [
            ("rivers", "regionalRiver"),
            ("waters", "regionalWater"),
            ("places", "regionalNaturePin"),
        ]:
            self.global_features(base / "scenery" / (name + ".geojson.gz"), lambda f, layer=layer: layer)
        for sub in ["relief", "mountains"]:
            file = base / sub / "index.js"
            meta = json.loads(file.read_text().split("export default ")[1].strip().removesuffix(";"))
            sheet = next(s for s in meta["sheets"] if s["name"] in ("taiwan", "taiwan-highlands"))
            with Image.open(base / sub / (sheet["name"] + ".webp")) as image:
                alpha = np.array(image.getchannel("A"))
            top, right, bottom = sheet["coordinates"][0], sheet["coordinates"][1], sheet["coordinates"][2]
            merc = lambda lat: math.asinh(math.tan(math.radians(lat)))
            for i, r in enumerate(self.rows):
                pt = self.g[i].representative_point()
                x = math.floor((pt.x - top[0]) / (right[0] - top[0]) * alpha.shape[1])
                y = math.floor(
                    (merc(top[1]) - merc(pt.y)) / (merc(top[1]) - merc(bottom[1])) * alpha.shape[0]
                )
                if 0 <= y < alpha.shape[0] and 0 <= x < alpha.shape[1]:
                    r["counts"][sub + "AlphaAtInterior"] = int(alpha[y, x])
        # Regional river/water layers fade at z13.5. Record geometry separately from z17 street coverage.

    def raw_osm(self, path):
        # Independently inventory common landscape / watercourse sources absent from the
        # city170 taxonomy. Full original coordinates include multi-way relation members.
        def category(t):
            val = t.get("waterway")
            if val in ("stream", "river", "canal", "ditch", "drain"):
                return "waterway/" + val
            val = t.get("landuse")
            if val in (
                "farmland",
                "orchard",
                "allotments",
                "vineyard",
                "cemetery",
                "quarry",
                "farmyard",
                "plant_nursery",
            ):
                return "landuse/" + val
            val = t.get("natural")
            if val in (
                "cliff",
                "bare_rock",
                "scree",
                "heath",
                "sand",
                "beach",
                "shingle",
                "fell",
                "rock",
                "ridge",
                "valley",
                "peak",
                "spring",
            ):
                return "natural/" + val
            return None

        def records():
            with gzip.open(path, "rb") as f:
                yield from ijson.items(f, "elements.item", use_float=True)

        relations = []
        members = set()
        for e in records():
            if e["type"] == "relation" and (c := category(e.get("tags", {}))):
                relations.append((c, e))
                members.update(m["ref"] for m in e.get("members", []) if m["type"] == "way")
        ids = array("q")
        lng = array("d")
        lat = array("d")
        saved = {}
        idx = xx = yy = None
        groups = defaultdict(list)
        cells_hit = Counter()
        invalid = Counter()

        def flush(k):
            if not groups[k]:
                return
            src, dest = self.tree.query([g for g, _ in groups[k]], predicate="intersects")
            local = np.unique(src)
            cells_hit[k] += len(local)
            for j, i in zip(src, dest):
                self.rows[i]["counts"]["raw/" + k] += 1
                if not self.direct[self.rows[i]["id"]]:
                    self.rows[i].setdefault("rawEvidence", {}).setdefault(k, []).append(groups[k][j][1])
            groups[k].clear()

        def add(c, g, ident):
            if g is None or g.is_empty:
                return
            groups[c].append((g, ident))
            if len(groups[c]) >= 700:
                flush(c)

        for e in records():
            et = e["type"]
            oid = e["id"]
            t = e.get("tags", {})
            c = category(t)
            if et == "node":
                ids.append(oid)
                lng.append(e["lon"])
                lat.append(e["lat"])
                if c:
                    add(c, geo.Point(e["lon"], e["lat"]), "node/" + str(oid))
                continue
            if et != "way" or not (c or oid in members):
                continue
            if idx is None:
                idx = np.array(ids)
                xx = np.array(lng)
                yy = np.array(lat)
                order = np.argsort(idx)
                idx = idx[order]
                xx = xx[order]
                yy = yy[order]
            refs = e.get("nodes", [])
            j = np.searchsorted(idx, refs)
            if len(refs) < 2 or np.any(j >= len(idx)) or not np.array_equal(idx[j], refs):
                invalid["missingWayNodes"] += 1
                continue
            coords = np.column_stack([xx[j], yy[j]])
            line = LineString(coords)
            if oid in members:
                saved[oid] = line
            if c:
                area = (
                    refs[0] == refs[-1]
                    and len(refs) >= 4
                    and (
                        c.startswith("landuse/")
                        or c.split("/")[-1]
                        in ("bare_rock", "scree", "heath", "sand", "beach", "shingle", "fell")
                    )
                )
                add(c, geo.make_valid(Polygon(coords)) if area else line, "way/" + str(oid))
        for c, e in relations:
            pieces = [
                (m.get("role", ""), saved.get(m["ref"])) for m in e.get("members", []) if m["type"] == "way"
            ]
            if not pieces or any(g is None for _, g in pieces):
                invalid["incompleteRelation"] += 1
                continue
            line = unary_union(
                [g for role, g in pieces if role in ("", "outer", "main_stream", "side_stream")]
            )
            if e["tags"].get("type") in ("multipolygon", "boundary"):
                geom = unary_union(list(polygonize(line)))
                holes = unary_union([g for role, g in pieces if role == "inner"])
                if not holes.is_empty:
                    geom = geom.difference(unary_union(list(polygonize(holes))))
            else:
                geom = line
            add(c, geom, "relation/" + str(e["id"]))
        for c in groups:
            flush(c)
        self.detail["rawCandidates"] = {
            "uniqueIntersectingRecords": dict(cells_hit),
            "unusable": dict(invalid),
            "meaning": "Source records by geometry; relation members may also have thematic tags. Base-map tile styling is not inspected.",
        }

    def final(self, output):
        output.mkdir(parents=True, exist_ok=True)
        summary = {
            "uniqueCells": len(self.rows),
            "packs": len(self.index["packs"]),
            "edgeCells": sum(r["edge"] for r in self.rows),
            "multiDistrictCells": sum(len(r["districts"]) > 1 for r in self.rows),
            "details": self.detail,
            "validationFailures": dict(self.fail),
            "examples": dict(self.examples),
            "outsideGrid": dict(self.outside),
        }
        for r in self.rows:
            c = r["counts"]
            c["matchedFrontageAfter"] = c["matchedFrontage"] + c["recoveredMatchedFrontage"]
            if (
                not self.direct[r["id"]]
                and not r["edge"]
                and not c["streetFarmland"]
                and not c["streetWaterway"]
            ):
                r["detailCoverage"] = "保留一般底圖"
        summary["distinctSourceTotals"] = dict(sorted(self.totals.items()))
        summary["sourceEmptyCells"] = [r["id"] for r in self.rows if not self.direct[r["id"]]]
        criteria = {
            "osmFootprint": ["osm/building"],
            "surveyVertex": ["surveyTilesWithVertices"],
            "street": ["osm/road", "osm/walk"],
            "school": ["schoolArea", "schoolLabel"],
            "mappedNature": ["osm/forest", "osm/park", "osm/water", "osm/tree", "inventoryTree"],
            "publicPlace": ["publicPlace"],
            "shop": ["shopSearch"],
            "frontage": ["matchedFrontage", "recoveredMatchedFrontage"],
            "pedestrian": ["pedestrianPath"],
            "sport": ["osm/pitch"],
        }
        district = {}
        for name in self.district_names + ["全市"]:
            subset = [r for r in self.rows if name == "全市" or name in r["districts"]]
            district[name] = {
                "cells": len(subset),
                "emptySource": sum(not self.direct[r["id"]] for r in subset),
                **{
                    k: sum(any(r["counts"].get(l, 0) > 0 for l in layers) for r in subset)
                    for k, layers in criteria.items()
                },
            }
        summary["districts"] = district
        summary["allLayersCellCounts"] = dict(
            sorted(Counter(k for r in self.rows for k, v in r["counts"].items() if v).items())
        )
        summary["method"] = {
            "counts": "Each canonical feature counted once per intersected cell; district boundaries can share cells. District totals must not be added.",
            "surveyTilesWithVertices": "Source 200 m survey tiles with at least one decoded renderer XY vertex inside the 170 m cell; zero does not exclude a polygon crossing the cell.",
            "z17": "This is a source / dependency audit, not screenshot coverage. Raster relief alpha is sampled at one interior point. Regional water lines and areas have maxzoom 13.5; external live vector tiles are not counted.",
            "frontage": "Searchable shops can have pins without a matched street-level wall. Clusters, zoom and collisions affect display.",
            "supplements": "streetFarmland and streetWaterway are high-zoom add-ons to the canonical main packs. A zero sourceRefs does not determine total cell coverage. Raw OSM counts are independently reconstructed, including relation members with their own tags.",
            "prepared": "Per-cell entries from the generator, not actual trees or unique buildings.",
        }
        (output / "taipei-170m-summary.json").write_text(
            json.dumps(summary, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
        )
        with (output / "taipei-170m-cells.jsonl").open("w") as f:
            for r in self.rows:
                r["sourceRefs"] = len(self.direct[r["id"]])
                r["counts"] = {k: v for k, v in sorted(r["counts"].items()) if v}
                f.write(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(
            json.dumps(
                {
                    "path": str(output),
                    "districts": district,
                    "failureCounts": self.fail,
                    "rawEmpty": len(summary["sourceEmptyCells"]),
                },
                ensure_ascii=False,
            )
        )
        lines = [
            "# 台北市 170 公尺逐格稽核",
            "",
            f"市界內 {len(self.rows):,} 格，{self.index['stats']['packs']} 個圖資包。{len(self.fail)} 類結構檢查失敗。跨區格在各區分別計入，全市欄位已去重。",
            "",
            "|行政區|格數|道路或步徑|學校範圍或名稱|有店家搜尋點|有匹配店面|自然圖徵或樹籍|有人行路線|",
            "|---|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for name, values in district.items():
            lines.append(
                "|"
                + name
                + "|"
                + "|".join(
                    f"{values[k]:,}"
                    for k in ["cells", "street", "school", "shop", "frontage", "mappedNature", "pedestrian"]
                )
                + "|"
            )
        e = [r for r in self.rows if not self.direct[r["id"]]]

        def number(key):
            return sum(bool(r["counts"].get(key)) for r in e)

        cfg = self.detail["drawingEligibility"]
        fs = self.detail["frontages"]
        lines += [
            "",
            "### 來源與修後圖層",
            "",
            f"- 原始主圖包有 {len(e)} 個零引用格，其中 {number('raw/landuse/farmland')} 格有原始農地，修後農地圖層覆蓋 {number('streetFarmland')} 格，街道尺度水道圖層覆蓋 {number('streetWaterway')} 格；可重疊。",
            f"- 店家搜尋候選 {fs['input']:,} 個。原匹配店面 {fs['matched']:,} 個，修後 {fs['afterRecovery']:,} 個。尚無匹配外牆 {fs['unmatchedAfterRecovery']:,} 個。",
            f"- {self.detail['categoryInventory']['walk/steps']:,} 段階梯來源中，{cfg['groundStairTreads']:,} 段符合實際圖層篩選。{cfg['singleCourtMarkings']:,} 個球場符合程式的運動種類、尺寸和形狀條件。",
            f"- 全市新增的 {self.totals['streetFarmland']:,} 筆農地／果園圖徵與 {self.totals['streetWaterway']:,} 筆地表水道分別覆蓋 {summary['allLayersCellCounts'].get('streetFarmland', 0):,} 和 {summary['allLayersCellCounts'].get('streetWaterway', 0):,} 格。",
            f"- 民航客運停機坪 {self.totals['publicTerminalApron']} 筆，覆蓋 {summary['allLayersCellCounts'].get('publicTerminalApron', 0)} 格。",
            f"- {summary['allLayersCellCounts'].get('openGroundCrownsRemoved', 0):,} 格內共扣除 {sum(r['counts'].get('openGroundCrownsRemoved', 0) for r in self.rows):,} 個草原與濕地示意樹冠。樹籍實測點保留。",
            "",
            "本表統計圖資與圖層的輸入。圖面標籤仍受縮放、視角、遮擋和碰撞排版影響。對外部即時底圖與逐格實機畫面未做驗收。",
        ]
        lines += [
            "",
            "### 主包零引用格的來源核對",
            "",
            "|格號|行政區|市界內面積 m²|原始 OSM 分類|新增街道尺度圖徵|",
            "|---|---|---:|---|---|",
        ]
        for r in e:
            c = r["counts"]
            raw = ", ".join(k.removeprefix("raw/") for k in c if k.startswith("raw/"))
            overlays = "、".join(
                n for k, n in [("streetFarmland", "農地"), ("streetWaterway", "水道")] if c.get(k)
            )
            if r.get("detailCoverage"):
                continue
            lines.append(
                f"|{r['id']}|{'、'.join(r['districts'])}|{r['areaM2']:,.1f}|{raw or '稽核分類未相交'}|{overlays or '—'}|"
            )
        ordinary = sum(bool(r.get("detailCoverage")) for r in e)
        if ordinary:
            lines.extend(["", f"另有 {ordinary} 個完整格保留一般底圖。"])
        (output / "taipei-170m-summary.md").write_text("\n".join(lines) + "\n")
        return bool(self.fail)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", type=Path, required=True)
    p.add_argument("--osm", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    audit = Audit(args.data)
    for name in ["packs", "verify_zero_refs", "survey", "nationwide"]:
        print("Checking " + name, flush=True)
        getattr(audit, name)()
    print("Checking original OSM", flush=True)
    audit.raw_osm(args.osm)
    audit.detail["inputs"] = {
        str(path.name): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [
            args.data / "city170/index.json",
            args.data / "city170/grid.json.gz",
            args.data / "survey-index.json",
            args.data / "city170-frontages/summary.json",
            args.data / "city170-open-ground.json.gz",
            args.data / "city170-farmland.json.gz",
            args.data / "city170-airfield.json.gz",
            args.data / "city170-waterways.json.gz",
            *[
                args.data.parent / f
                for f in [
                    "city170-ground.js",
                    "city170-grade-ids.js",
                    "city170-style.js",
                    "city170-courts.js",
                    "taipei-frontage-pack.js",
                    "taipei-shopfront-recoveries.js",
                    "dihua-north-frontages.js",
                    "taipei-ground-frontages.js",
                    "taipei-address-frontages.js",
                ]
            ],
            args.osm,
        ]
    }
    raise SystemExit(audit.final(args.output))


if __name__ == "__main__":
    main()

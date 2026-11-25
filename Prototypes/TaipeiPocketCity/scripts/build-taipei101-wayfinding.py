"""Produce the two authored floor sketches in the coordinates of the Pocket City mall.

Uses NumPy and Shapely 2. Run with the runtime mall module and an output JS path.
Control picks are measured on 1000 × 1000 previews of the official floor diagrams.
Simplified wayfinding geometry is drawn independently of the official SVG paths.
"""

import argparse
import json
from pathlib import Path

import numpy as np
from shapely import get_parts, transform
from shapely.geometry import LineString, Point, Polygon, mapping, shape


SOURCES = {
    "1F": ("f1.svg", "4cc771af350175a99e4618b2b3e3ee73a5318a50fb4f06e6fb5a4f726a3c7f68"),
    "B1": ("b1.svg", "dc64aa52582d409c3dbb63680bc120542c0bb73554358b8a17042e8a9a337a2e"),
}
DIAGRAM_BASE = "https://www.taipei-101.com.tw/asset/img/map/"
ENTRANCES = (
    ("node/12390532418", (472, 94), "北側入口"),
    ("node/12390532419", (850, 218), "松智路入口"),
    ("node/12390532420", (216, 843), "信義路入口"),
)
# Numbered lift cores 1–4 appear on both schematic diagrams.
LIFTS = {
    "1F": [(707, 585), (592, 701), (653, 117), (124, 668)],
    "B1": [(721, 528), (564, 671), (618, 79), (68, 596)],
}
AREAS = {
    "1F": [
        ("中環", "centre", [(204, 194), (258, 175), (322, 201), (360, 249), (354, 310),
                          (316, 346), (264, 347), (217, 311), (186, 251)]),
        ("松智東", "east", [(653, 183), (706, 161), (757, 191), (782, 229), (761, 277),
                           (712, 307), (658, 281), (629, 232)]),
        ("信義南", "south", [(199, 635), (249, 618), (294, 641), (322, 693), (299, 747),
                           (250, 774), (199, 752), (166, 697)]),
    ],
    "B1": [
        ("美食廣場", "food", [(347, 308), (495, 308), (592, 373), (617, 455), (551, 515),
                             (511, 540), (405, 534), (375, 466), (395, 412), (348, 373)]),
        ("伴手禮區", "gifts", [(255, 606), (312, 579), (411, 604), (452, 650), (443, 712),
                               (336, 729), (260, 695)]),
    ],
}
# Group opaque wings alongside the principal walks, without individual shop divisions.
BLOCKS = {
    "1F": [
        [(112, 109), (174, 109), (171, 171), (147, 210), (112, 210)],
        [(514, 105), (590, 105), (590, 155), (514, 152)],
        [(483, 477), (492, 477), (492, 774), (323, 774), (333, 691),
         (310, 625), (266, 595), (266, 509), (413, 509)],
        [(501, 244), (561, 250), (613, 286), (690, 341), (733, 339),
         (734, 396), (540, 396), (540, 347), (501, 328)],
    ],
    "B1": [
        [(124, 72), (174, 72), (174, 144), (146, 188), (124, 188)],
        [(281, 73), (418, 74), (427, 99), (427, 171), (317, 171), (281, 144)],
        [(511, 87), (621, 86), (662, 113), (632, 162), (512, 168)],
        [(66, 300), (155, 299), (171, 329), (171, 404), (124, 404), (124, 355), (66, 355)],
        [(68, 438), (162, 438), (161, 531), (68, 531)],
    ],
}
WALKS = {
    "1F": [
        (39, [(248, 99), (249, 182), (265, 253), (339, 215), (454, 186), (530, 190),
              (618, 215), (699, 240), (842, 218)]),
        (39, [(247, 823), (246, 709), (190, 615), (188, 506), (218, 365), (265, 253)]),
        (27, [(189, 470), (390, 466), (466, 395), (465, 257), (454, 186), (465, 99)]),
    ],
    "B1": [
        (31, [(71, 244), (198, 244), (267, 224), (453, 207), (574, 208), (719, 206), (791, 205)]),
        (28, [(253, 230), (220, 347), (215, 469), (218, 586), (212, 665), (280, 713), (316, 725)]),
        (33, [(265, 243), (315, 294), (386, 341), (437, 418), (471, 463),
              (476, 527), (438, 576), (376, 601), (376, 656), (324, 706)]),
    ],
}
MARKS = {
    "1F": [
        ("手扶梯", "escalator", (208, 196)), ("手扶梯", "escalator", (779, 240)),
        ("手扶梯", "escalator", (225, 623)), ("電梯", "lift", (124, 714)),
        ("電梯", "lift", (692, 118)),
    ],
    "B1": [
        ("手扶梯", "escalator", (304, 292)), ("手扶梯", "escalator", (782, 206)),
        ("手扶梯", "escalator", (217, 602)), ("電梯", "lift", (66, 633)),
        ("電梯", "lift", (655, 80)),
    ],
}


def calibrate(entrances):
    # Degree coordinates are sufficient for interpolating on the 120 m retail wing.
    # Calibrate the ground diagram to three mutually independent OSM entrance points.
    surface = np.linalg.solve(
        [[*pixel, 1] for _, pixel, _ in ENTRANCES],
        [entrances[key] for key, _, _ in ENTRANCES],
    )
    pairs = [[x, -y, 1, 0] if axis == 0 else [y, x, 0, 1] for x, y in LIFTS["B1"] for axis in range(2)]
    scale, skew, dx, dy = np.linalg.lstsq(pairs, np.ravel(LIFTS["1F"]), rcond=None)[0]
    cross_floor = np.array([[scale, skew, 0], [-skew, scale, 0], [dx, dy, 1]])
    residuals = np.linalg.norm(np.column_stack([LIFTS["B1"], np.ones(4)]) @ cross_floor[:, :2] - LIFTS["1F"], axis=1)
    return {"1F": surface, "B1": cross_floor @ surface}, residuals


def assemble(venue):
    outline = shape(venue["footprint"])
    entrances = {f["id"]: f["geometry"]["coordinates"] for f in venue["entrances"]["features"]}
    transforms, residuals = calibrate(entrances)
    plans = {}
    for label, matrix in transforms.items():
        features = []

        def project(geometry):
            return transform(geometry, lambda coords: np.column_stack([coords, np.ones(len(coords))]) @ matrix)

        def feature(geometry, role, name="", style=""):
            def quantize(value):
                return [quantize(x) for x in value] if isinstance(value, (list, tuple)) else round(value, 8)
            coords = quantize(mapping(geometry)["coordinates"])
            return dict(type="Feature", geometry=dict(type=geometry.geom_type, coordinates=coords),
                        properties=dict(name=name, role=role, style=style, floor=label))

        def polygons(geometry):
            return [part for part in get_parts(project(geometry).intersection(outline))
                    if part.geom_type == "Polygon" and part.area > 1e-11]

        for ring in BLOCKS[label]:
            features.extend(feature(part, "block") for part in polygons(Polygon(ring)))
        for width, points in WALKS[label]:
            for part in polygons(LineString(points).buffer(width / 2, quad_segs=3)):
                features.append(feature(part, "walk"))
        for name, style, ring in AREAS[label]:
            parts = polygons(Polygon(ring))
            for part in parts:
                features.append(feature(part, "area", style=style))
            largest = max(parts, key=lambda p: p.area)
            features.append(feature(largest.representative_point(), "zone", name, style))
        for name, role, xy in MARKS[label]:
            mark = project(Point(xy))
            if not outline.covers(mark):
                raise ValueError(f"{label} {name} is outside the retail wing")
            features.append(feature(mark, role, name))
        if label == "1F":
            for key, _, name in ENTRANCES:
                features.append(feature(Point(entrances[key]), "entrance", name, "east" if key == ENTRANCES[1][0] else ""))
        filename, checksum = SOURCES[label]
        plans[label] = dict(source=DIAGRAM_BASE + filename, sourceSHA256=checksum,
                            drawing=dict(type="FeatureCollection", features=features))
    return plans, residuals


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mall", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    venue = json.loads(args.mall.read_text().split("export const taipei101Indoor=", 1)[1].strip().removesuffix(";"))
    plans, residuals = assemble(venue)
    args.output.write_text(
        "// Generated by scripts/build-taipei101-wayfinding.py. Two approximate indoor sketches.\n"
        + "export const mallWayfinding=" + json.dumps(plans, ensure_ascii=False, separators=(",", ":")) + ";\n"
    )
    print("B1 lift-control residuals in source preview pixels:", residuals.round(1).tolist())
    print({label: len(plan["drawing"]["features"]) for label, plan in plans.items()})


if __name__ == "__main__":
    main()

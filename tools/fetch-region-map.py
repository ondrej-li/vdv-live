"""Fetch the region's roads and rivers from OpenStreetMap, for drawing the app icon.

Reuses the stop pipeline's Overpass helper and its region bounding box, so the icon
covers exactly the area the app's feed does. `make icon` runs this the first time and
caches the answer under build/: it is a megabyte of coordinates for a 1024 pixel
picture, and OpenStreetMap is where it comes from rather than the repository.

The data is OpenStreetMap, (c) OpenStreetMap contributors, published under the Open
Database Licence 1.0 (https://www.openstreetmap.org/copyright). Anything drawn from
it has to say so, which is why the acknowledgements screen credits OpenStreetMap.

Only the classes the icon draws are kept: the motorways and the numbered routes, and
the rivers. The region's minor roads are a mesh at icon size, and its standing water
comes back from Overpass as very large polygons that fill the picture with pale
blocks, so neither is worth the bytes.

Usage: python3 tools/fetch-region-map.py [output.json]
"""

import json
import os
import sys

sys.path.insert(0, ".github/skills/stop-positions/scripts")
import common  # noqa: E402

DEFAULT_OUTPUT = "build/icon/region-map.json"
BBOX = common.REGION_BBOX
ATTEMPTS = 3
DECIMALS = 4

ROADS_QUERY = """
[out:json][timeout:300];
(
  way["highway"~"^(motorway|trunk|primary)$"](%s);
);
out geom;""" % BBOX

RIVER_QUERY = """
[out:json][timeout:300];
(
  way["waterway"~"^(river|canal)$"](%s);
);
out geom;""" % BBOX


def ask(query, label):
    """Overpass is busy often enough that one empty answer means nothing."""
    for attempt in range(1, ATTEMPTS + 1):
        elements = common.ask_overpass(query)
        if elements:
            print("%s: %d elements" % (label, len(elements)))
            return elements
        print("%s: empty answer, attempt %d of %d" % (label, attempt, ATTEMPTS))
    raise SystemExit(
        "the %s query came back empty %d times; Overpass may be busy - try again later"
        % (label, ATTEMPTS)
    )


def ways(elements, wanted):
    """The geometry of each element, rounded and as [latitude, longitude] pairs."""
    lines = []
    for element in elements:
        tags = element.get("tags") or {}
        if tags.get("highway", tags.get("waterway")) not in wanted:
            continue
        geometry = element.get("geometry") or []
        points = [
            [round(point["lat"], DECIMALS), round(point["lon"], DECIMALS)]
            for point in geometry
            if "lat" in point and "lon" in point
        ]
        if len(points) > 1:
            lines.append(points)
    return lines


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUTPUT
    print("bbox", BBOX)

    roads = ask(ROADS_QUERY, "roads")
    rivers = ask(RIVER_QUERY, "rivers")

    document = {
        "bbox": BBOX,
        "source": "OpenStreetMap, ODbL 1.0",
        "motorway": ways(roads, {"motorway"}),
        "trunk": ways(roads, {"trunk"}),
        "primary": ways(roads, {"primary"}),
        "river": ways(rivers, {"river", "canal"}),
    }

    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(path, "w") as handle:
        json.dump(document, handle, separators=(",", ":"))
    print(
        "wrote %s: %d motorway, %d trunk, %d primary, %d river ways, %.0f KB"
        % (
            path,
            len(document["motorway"]),
            len(document["trunk"]),
            len(document["primary"]),
            len(document["river"]),
            os.path.getsize(path) / 1024,
        )
    )


if __name__ == "__main__":
    main()

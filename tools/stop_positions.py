#!/usr/bin/env python3
"""Work out where the region's bus stops are, from sources that publish positions.

The timetables we ship carry stop names but no geometry: JDF's `Zastavky.txt` has no
coordinate columns (its columns 7-12 are tariff zones) and the ministry's NeTEx export
leaves every one of its 327,110 `<Location />` elements empty. Positions therefore have
to come from somewhere else, and OpenStreetMap is the only source that has them for this
region - the region itself publishes nothing, and neither the live feed nor the state
map carries bus stops.

So positions are *matched*, not looked up, and matching is where this can go wrong. Three
rules keep it honest:

*   Candidates come from inside the region's administrative boundary, not a bounding box,
    so a village with a common name cannot be answered by its namesake next door.
*   A name is only accepted in the forms a timetable would print it in, after expanding
    the abbreviations JDF uses and OSM does not (`nám.` / `náměstí`, `rozc.` / `rozcestí`).
    A match with no distinguishing part left (`Petrovice`) has to be near the village.
*   Every position is then checked against the timetable itself: the run lists how far
    each call is from the start, so two consecutive stops imply a distance, and a straight
    line longer than that distance allows means the position is wrong. Wrong positions are
    replaced by the village centre rather than published.

Output is a lookup table keyed by the normalised stop name the app already shows, with the
kind of match (`osm-name`, `osm-village`, `osm-near`, `place`) and an accuracy in metres
attached. Only positions from a real OpenStreetMap stop are written by default; the village
centres a stop can fall back to are behind `--include-village-centres`, because they are
within a few hundred metres of everything in the village and no better than a guess for the
stop itself.

    make stops
    python3 tools/stop_positions.py /tmp/jdf/JDF.zip VdvLive/Resources/stop-positions.json

The archive parse and the OpenStreetMap answers are cached under `build/stops/`;
`REFRESH_JDF=1` or `REFRESH_OSM=1` forces either to be asked for again.
"""

import csv
import io
import json
import math
import os
import re
import sys
import unicodedata
import urllib.parse
import urllib.request
import zipfile
from collections import defaultdict

# JDF's Zasspoje.txt columns, the same ones the app's parser uses.
COL_SERVICE, COL_STOP, COL_DISTANCE = 1, 3, 9

# Both the archive parse and the OpenStreetMap answers are cached here; build/ is ignored.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_DIR = os.path.join(REPO_ROOT, "build", "stops")

REGION = {"JI", "TR", "PE", "HB", "ZR"}         # the districts of the Vysočina Region
# The JDF district code is the okres the stop is in, which is how the region's stops are
# kept apart from villages of the same name in the next district or the next region.
DISTRICT_AREA = {"JI": "Jihlava", "TR": "Třebíč", "ZR": "Žďár nad Sázavou",
                 "HB": "Havlíčkův Brod", "PE": "Pelhřimov"}
DISTRICT_SELECTOR = 'area["boundary"="administrative"]["admin_level"="6"]["name"="%s"]'
REGION_BBOX = "48.83,14.90,49.93,16.38"

# A position that implies a longer straight line than this multiple of the timetable's
# own distance between the two calls is not believed. Roads are not straight, so the
# slack is generous; a wrong village is out by tens of kilometres, not by tens of per cent.
DISTANCE_SLACK, DISTANCE_FLOOR_KM = 1.6, 3.0
# A matched position has to be within this of another stop the same line calls at.
ISOLATION_KM = 12.0
# A match on the village name alone has to be this close to the village centre.
BARE_NAME_RADIUS_KM = 15.0
# A stop named after a hamlet, filed in OSM under the hamlet alone, has to be this close.
HAMLET_RADIUS_KM = 5.0

ABBREVIATIONS = [
    ("aut.nádr.", "autobusové nádraží"), ("aut.st.", "autobusové staveniště"),
    ("žel.st.", "železniční stanice"), ("žel.zast.", "železniční zastávka"),
    ("žel.", "železniční"), ("nám.", "náměstí"), ("rozc.", "rozcestí"),
    ("zast.", "zastávka"), ("st.", "stanice"), ("šk.", "škola"),
    ("zš", "základní škola"), ("zšk", "základní škola"), ("obú", "obecní úřad"),
    ("oú", "obecní úřad"), ("rest.", "restaurace"), ("hosp.", "hospoda"),
    ("mot.", "motorest"), ("kost.", "kostel"), ("křiž.", "křižovatka"),
    ("zem.", "zemědělské"), ("ul.", "ulice"), ("n.sáz.", "nad sázavou"),
    ("n.osl.", "nad oslavou"), ("n.jihl.", "nad jihlavou"), ("točna", "obratiště"),
    ("konečná", "obratiště"),
]


def expand(text):
    lowered = text.lower()
    for short, long in ABBREVIATIONS:
        lowered = lowered.replace(short, long)
    return lowered


def normalise(text):
    """Case, diacritics and punctuation washed out, so both spellings meet."""
    text = unicodedata.normalize("NFKD", expand(text))
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", text)


def key_of(text):
    """The key the app looks a stop up by: case, diacritics and punctuation only.

    No abbreviations are expanded here. The app folds the name it displays and nothing
    else, so the keys have to be folded the same way; expanding `nám.` is only ever used
    to compare our name with OpenStreetMap's.
    """
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", text)


def without_district(muni):
    return re.sub(r"\s*\[[A-Z]{2}\]\s*$", "", muni).strip()


def display_name(muni, part, local):
    """How the app shows a stop: municipality, part, local name, comma-joined."""
    return ",".join(p.strip() for p in (without_district(muni), part, local) if p and p.strip())


def name_forms(muni, part, local):
    """Every order the pieces of a stop name turn up in, most specific first."""
    base = without_district(muni)
    forms = []
    if local:
        forms.append(",".join(x for x in (base, local) if x))
        if part:
            forms.append(",".join(x for x in (base, part, local) if x))
            forms.append(",".join(x for x in (base, local, part) if x))
    if part:
        forms.append(",".join(x for x in (base, part) if x))
    forms.append(base)
    seen, unique = set(), []
    for form in forms:
        key = normalise(form)
        if key and key not in seen:
            seen.add(key)
            unique.append(key)
    return unique


def read_rows(archive, name):
    if name not in archive.namelist():
        return []
    rows = []
    for line in archive.read(name).decode("cp1250", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        if line.endswith(";"):
            line = line[:-1]
        rows.append(next(csv.reader([line], delimiter=",", quotechar='"')))
    return rows


def read_archive(path, cache_path):
    """Every stop in the region, and one representative run of each line with distances."""
    if os.path.exists(cache_path) and os.environ.get("REFRESH_JDF") != "1":
        try:
            cached = json.load(open(cache_path))
        except ValueError:                     # a cache left half-written is no cache
            cached = None
        if cached:
            print("using cached archive parse", file=sys.stderr)
            return cached

    stops, orders, runs = {}, {}, {}
    with zipfile.ZipFile(path) as outer:
        names = [n for n in outer.namelist() if n.lower().endswith(".zip")]
        for index, entry in enumerate(names):
            with zipfile.ZipFile(io.BytesIO(outer.read(entry))) as inner:
                table, in_region = {}, False
                for row in read_rows(inner, "Zastavky.txt"):
                    if len(row) < 6:
                        continue
                    table[row[0]] = (row[1], row[2], row[3])
                    if row[4] in REGION:
                        in_region = True
                        stops.setdefault("\x1f".join((row[1], row[2], row[3])), {"district": row[4]})
                if not in_region:
                    continue
                orders[entry] = [list(table[row[3]]) for row in read_rows(inner, "Zaslinky.txt")
                                 if len(row) > 3 and row[3] in table]

                # Distances come per run; the first run with distances is enough to
                # judge whether two positions can be reached from one another.
                collected = defaultdict(list)
                for row in read_rows(inner, "Zasspoje.txt"):
                    if len(row) <= COL_DISTANCE or row[COL_STOP] not in table:
                        continue
                    distance = row[COL_DISTANCE].strip()
                    if distance.isdigit():
                        collected[row[COL_SERVICE]].append([list(table[row[COL_STOP]]),
                                                            int(distance)])
                best = max(collected.values(), key=len, default=[])
                if len(best) > 1:
                    runs[entry] = best
            if index % 2000 == 0:
                print("  archive %d/%d" % (index, len(names)), file=sys.stderr)

    document = {"stops": stops, "orders": orders, "runs": runs}
    json.dump(document, open(cache_path, "w"))
    return document


OVERPASS = {
    "stops": """
[out:json][timeout:180];
%s->.r;
(
  node["highway"="bus_stop"](area.r);
  node["public_transport"="stop_position"]["bus"="yes"](area.r);
  node["public_transport"="platform"](area.r);
  way["highway"="platform"](area.r);
  way["public_transport"="platform"](area.r);
);
out center tags;""",
    "places": """
[out:json][timeout:180];
%s->.r;
node["place"~"^(city|town|village|hamlet|suburb)$"](area.r);
out center tags;""",
}
OVERPASS_BBOX = {
    "stops": """
[out:json][timeout:180];
(
  node["highway"="bus_stop"](%s);
  node["public_transport"="stop_position"]["bus"="yes"](%s);
  node["public_transport"="platform"](%s);
  way["highway"="platform"](%s);
  way["public_transport"="platform"](%s);
);
out center tags;""" % ((REGION_BBOX,) * 5),
    "places": """
[out:json][timeout:180];
node["place"~"^(city|town|village|hamlet|suburb)$"](%s);
out center tags;""" % REGION_BBOX,
}
OVERPASS_BBOX = {
    "stops": """
[out:json][timeout:180];
(
  node["highway"="bus_stop"](%s);
  node["public_transport"="stop_position"]["bus"="yes"](%s);
  node["public_transport"="platform"](%s);
  way["highway"="platform"](%s);
  way["public_transport"="platform"](%s);
);
out center tags;""" % ((REGION_BBOX,) * 5),
    "places": """
[out:json][timeout:180];
node["place"~"^(city|town|village|hamlet|suburb)$"](%s);
out center tags;""" % REGION_BBOX,
}


def ask_overpass(query):
    for endpoint in ("https://overpass-api.de/api/interpreter",
                     "https://overpass.kumi.systems/api/interpreter"):
        try:
            request = urllib.request.Request(
                endpoint,
                data=urllib.parse.urlencode({"data": query}).encode(),
                headers={"User-Agent": "vdv-live stop extractor (one-off build step)"},
            )
            return json.loads(urllib.request.urlopen(request, timeout=300).read())["elements"]
        except Exception as error:            # noqa: BLE001 - try the next mirror
            print("  %s: %s" % (endpoint, error), file=sys.stderr)
    return []


def fetch_osm(cache_path):
    """Stops and village centres, asked for one okres at a time.

    A bounding box would drag in the neighbouring regions, where a village of the same
    name answers for ours; the district boundary is the same line JDF draws.
    """
    if os.path.exists(cache_path) and os.environ.get("REFRESH_OSM") != "1":
        print("using cached OSM response", file=sys.stderr)
        return json.load(open(cache_path))
    out = {}
    for code, okres in DISTRICT_AREA.items():
        for label, query in OVERPASS.items():
            elements = ask_overpass(query % (DISTRICT_SELECTOR % okres))
            if len(elements) < 50:
                print("  %s/%s: empty, falling back to the bounding box" % (label, code),
                      file=sys.stderr)
                elements = ask_overpass(OVERPASS_BBOX[label])
            for element in elements:
                element["jdf_district"] = code
            out.setdefault(label, []).extend(elements)
            print("  %s %s: %d elements" % (code, label, len(elements)), file=sys.stderr)
    json.dump(out, open(cache_path, "w"))
    return out


def distance_km(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(h))


def index_osm(osm):
    """OSM stops and village centres, keyed by district and normalised name."""
    by_name = defaultdict(dict)
    places = defaultdict(dict)
    for element in osm["stops"]:
        tags = element.get("tags", {})
        name = tags.get("name")
        lat = element.get("lat") or (element.get("center") or {}).get("lat")
        lon = element.get("lon") or (element.get("center") or {}).get("lon")
        if name and lat is not None:
            by_name[element.get("jdf_district", "all")].setdefault(normalise(name), []).append(
                {"name": name, "lat": lat, "lon": lon})
    for element in osm["places"]:
        tags = element.get("tags", {})
        name, lat = tags.get("name"), element.get("lat")
        if name and lat is not None:
            places[element.get("jdf_district", "all")].setdefault(
                normalise(name), {"name": name, "lat": lat, "lon": element["lon"]})
    return by_name, places


def district_index(by_name, places, district):
    """The candidates to match against: the stop's own okres, or everything we have.

    Data fetched before the district scoping existed (or a bounding-box fallback) is kept
    under "all", which is still usable - the radii and the distance budget do the guarding
    then.
    """
    return (by_name.get(district) or by_name.get("all", {}),
            places.get(district) or places.get("all", {}))


def find_position(muni, part, local, by_name, places, allow_osm=True):
    """The best position we can defend for one stop, and how it was found."""
    base = without_district(muni)
    base_key = normalise(base)
    centre = places.get(base_key)
    home = (centre["lat"], centre["lon"]) if centre else None

    if allow_osm:
        for form in name_forms(muni, part, local):
            if form not in by_name:
                continue
            candidate = by_name[form][0]
            # A bare village name says nothing about which stop is meant, so it is only
            # accepted when it is somewhere near the village it claims to be in.
            if form == base_key and home:
                if distance_km(home, (candidate["lat"], candidate["lon"])) > BARE_NAME_RADIUS_KM:
                    continue
            return candidate, "osm-name", 40.0

        wanted = [w for w in (normalise(local), normalise(part)) if len(w) > 3]
        if base_key and wanted:
            for key, candidates in by_name.items():
                if key.startswith(base_key) and any(w in key for w in wanted):
                    return candidates[0], "osm-village", 150.0

        # A stop named after a hamlet is often filed in OSM under the hamlet alone,
        # with no municipality in front of it.
        if home and wanted:
            near = [candidate
                    for key, candidates in by_name.items() if any(w in key for w in wanted)
                    for candidate in candidates
                    if distance_km(home, (candidate["lat"], candidate["lon"])) <= HAMLET_RADIUS_KM]
            if near:
                nearest = min(near, key=lambda c: distance_km(home, (c["lat"], c["lon"])))
                return nearest, "osm-near", 250.0

    if centre:
        return centre, "place", 600.0
    return None, "none", None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    archive_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/stop_positions.json"
    include_village_centres = "--include-village-centres" in sys.argv
    print("including village centres: %s" % include_village_centres, file=sys.stderr)

    print("reading the archive...", file=sys.stderr)
    os.makedirs(CACHE_DIR, exist_ok=True)
    data = read_archive(archive_path,
                        os.environ.get("JDF_CACHE", os.path.join(CACHE_DIR, "archive.json")))
    stops, orders, runs = data["stops"], data["orders"], data["runs"]
    keys = [tuple(key.split("\x1f")) for key in stops]
    print("region stops: %d | lines: %d | runs with distances: %d"
          % (len(keys), len(orders), len(runs)), file=sys.stderr)

    print("asking OpenStreetMap...", file=sys.stderr)
    osm_cache = os.environ.get("OSM_CACHE", os.path.join(CACHE_DIR, "openstreetmap.json"))
    by_name, places = index_osm(fetch_osm(osm_cache))
    print("districts with OSM stops: %d | villages: %d"
          % (len(by_name), sum(len(v) for v in places.values())), file=sys.stderr)

    resolved, positions = {}, {}
    for muni, part, local in keys:
        district = stops["\x1f".join((muni, part, local))]["district"]
        local_stops, local_places = district_index(by_name, places, district)
        found, how, accuracy = find_position(muni, part, local, local_stops, local_places)
        resolved[(muni, part, local)] = (found, how, accuracy, district)
        if found and how.startswith("osm"):
            positions[(muni, part, local)] = (found["lat"], found["lon"])

    # Two guards, in the order of how much they can be trusted.
    #
    # A position that sits far from every other stop its line calls at is wrong: a bus
    # does not serve one stop twenty kilometres away from the rest of its route.
    called_out = set()
    for entry, order in orders.items():
        known = [(tuple(key), positions[tuple(key)]) for key in order
                 if tuple(key) in positions]
        if len(known) < 3:
            continue
        for key, position in known:
            others = [other for other_key, other in known if other_key != key]
            if all(distance_km(position, other) > ISOLATION_KM for other in others):
                called_out.add(key)

    # And the timetable's own distances, where they mean anything. They count down to the
    # end of the run, so on a route that loops back they are not monotone and the
    # difference between two calls says nothing about how far apart they are.
    looping = 0
    for entry, run in runs.items():
        distances = [km for _key, km in run]
        if distances != sorted(distances):
            looping += 1
            continue
        for step in range(1, len(run)):
            key, previous = tuple(run[step][0]), tuple(run[step - 1][0])
            if key not in positions or previous not in positions:
                continue
            gap = abs(run[step][1] - run[step - 1][1])
            allowed = max(DISTANCE_SLACK * gap, DISTANCE_FLOOR_KM)
            if distance_km(positions[key], positions[previous]) > allowed:
                called_out.add(key)
                called_out.add(previous)
    print("positions rejected: %d (runs skipped as looping: %d)" % (len(called_out), looping),
          file=sys.stderr)
    for key in called_out:
        _found, _how, _accuracy, district = resolved[key]
        local_stops, local_places = district_index(by_name, places, district)
        found, how, accuracy = find_position(key[0], key[1], key[2], local_stops, local_places,
                                             allow_osm=False)
        resolved[key] = (found, how, accuracy, district)

    table, counts, clashes = {}, defaultdict(int), defaultdict(int)
    for key, (found, how, _accuracy, _district) in resolved.items():
        counts[how] += 1
        if not found:
            continue
        if how == "place" and not include_village_centres:
            continue
        name = display_name(*key)
        row = {"name": name, "latitude": round(found["lat"], 5),
               "longitude": round(found["lon"], 5),
               "match": how, "accuracyMetres": _accuracy}
        lookup = key_of(name)
        existing = table.get(lookup)
        if existing and (existing["latitude"], existing["longitude"]) != (row["latitude"], row["longitude"]):
            # Two different stops share one display name, and the app cannot tell them
            # apart either. Keep whichever position we trust more.
            clashes[lookup] += 1
            if (row["accuracyMetres"] or 10_000) < (existing["accuracyMetres"] or 10_000):
                table[lookup] = row
            continue
        table[lookup] = row

    document = {
        "version": 1,
        "note": "Stop positions for the region's timetables, matched from OpenStreetMap by stop name.",
        "sources": [{"name": "OpenStreetMap", "licence": "ODbL 1.0",
                     "url": "https://www.openstreetmap.org/copyright"}],
        "stops": dict(sorted(table.items())),
    }
    json.dump(document, open(output_path, "w"), ensure_ascii=False, separators=(",", ":"))

    print()
    print("region stops:       %6d" % len(keys))
    for how in ("osm-name", "osm-village", "osm-near", "place", "none"):
        print("  %-12s %6d  %5.1f%%" % (how, counts[how], 100.0 * counts[how] / max(len(keys), 1)))
    placed = sum(counts[how] for how in ("osm-name", "osm-village", "osm-near"))
    print("published entries:  %6d  (name clashes resolved: %d)"
          % (len(table), sum(1 for _ in clashes)))
    print("with a real position: %d of %d published (%.1f%%)"
          % (sum(1 for row in table.values() if row["match"].startswith("osm")), len(table),
             100.0 * sum(1 for row in table.values() if row["match"].startswith("osm"))
             / max(len(table), 1)))
    print("stops placed from OSM: %d (%.1f%% of %d)"
          % (placed, 100.0 * placed / max(len(keys), 1), len(keys)))
    print("wrote %s (%.0f KB)" % (output_path, os.path.getsize(output_path) / 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())

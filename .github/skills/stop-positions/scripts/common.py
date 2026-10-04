#!/usr/bin/env python3
"""Shared helpers for the stop-position pipeline.

Everything the stages agree on lives here: how a stop name is folded, how JDF spells
things against how OpenStreetMap does, and where the intermediate files go. The stages
themselves are numbered scripts in this folder; `run_all.sh` runs them in order and
`SKILL.md` explains what each one is for.
"""

import csv
import difflib
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

# <root>/.github/skills/stop-positions/scripts/common.py
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "..", "..", "..", ".."))
SKILL_ROOT = os.path.join(REPO_ROOT, ".github", "skills", "stop-positions")
WORK = os.path.join(REPO_ROOT, "build", "stops")
BUNDLE = os.path.join(REPO_ROOT, "VdvLive", "Resources", "stop-positions.json")
REVIEW = os.path.join(REPO_ROOT, "docs", "stop-review.md")
MANUAL = os.path.join(SKILL_ROOT, "data", "manual_matches.json")

# The districts of the Vysocina Region, as JDF spells them, and the rectangle the
# OpenStreetMap extract is taken over.
REGION = {"JI", "TR", "PE", "HB", "ZR"}
REGION_BBOX = "48.83,14.90,49.93,16.38"

ARCHIVE = os.environ.get("JDF_ARCHIVE", "/tmp/jdf/JDF.zip")

# Written the way the timetables write it, said the way OpenStreetMap says it.
ABBREVIATIONS = [
    ("aut.nádr.", "autobusové nádraží"), ("aut.st.", "autobusové staveniště"),
    ("žel.st.", "železniční stanice"), ("žel.zast.", "železniční zastávka"),
    ("žel.", "železniční"), ("nám.", "náměstí"), ("rozc.", "rozcestí"),
    ("zast.", "zastávka"), ("st.", "stanice"), ("šk.", "škola"),
    ("zš", "základní škola"), ("zšk", "základní škola"), ("obú", "obecní úřad"),
    ("oú", "obecní úřad"), ("ků", "krajský úřad"), ("rest.", "restaurace"),
    ("hosp.", "hospoda"), ("mot.", "motorest"), ("kost.", "kostel"),
    ("křiž.", "křižovatka"), ("zem.", "zemědělské"), ("ul.", "ulice"),
    ("n.sáz.", "nad sázavou"), ("n.osl.", "nad oslavou"),
    ("n.jihl.", "nad jihlavou"), ("točna", "obratiště"), ("konečná", "obratiště"),
    # Last, because they are the shortest and would otherwise eat the longer forms
    # above: JDF writes "Střítež p.Křemešníkem" and "Štěpánov n.Svratkou".
    ("p.", "pod"), ("n.", "nad"),
]


def expand(text):
    lowered = text.lower()
    for short, long in ABBREVIATIONS:
        lowered = lowered.replace(short, long)
    return lowered


def normalise(text):
    """Case, diacritics and punctuation washed out, with abbreviations expanded."""
    text = unicodedata.normalize("NFKD", expand(text))
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", text)


def key_of(text):
    """The key the app looks a stop up by: case, diacritics and punctuation only.

    No abbreviations are expanded here. The app folds the name it displays and nothing
    else, so the table's keys have to be folded the same way; expanding `nám.` is only
    ever used to compare our name with OpenStreetMap's.
    """
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", text)


def tokens(text):
    """The words of a name, for comparing two of them."""
    text = unicodedata.normalize("NFKD", expand(text))
    text = "".join(c for c in text if not unicodedata.combining(c))
    return [t for t in re.split(r"[^a-z0-9]+", text) if t]


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


def stop_key(muni, part, local):
    """A stable identity for a stop across the stages, as one string."""
    return "\x1f".join((muni, part, local))


def split_key(key):
    muni, part, local = key.split("\x1f")
    return muni, part, local


def key_to_display(key):
    return display_name(*split_key(key))


def similarity(a, b):
    return difflib.SequenceMatcher(None, a, b).ratio()


def score_names(muni, part, local, candidate_name):
    """How much two names look like the same stop, between 0 and 1.

    The better of two readings: the whole names against each other, and the
    distinguishing words only, so that a shared municipality does not flatter a match and
    a missing one does not spoil it.
    """
    their = normalise(candidate_name)
    whole = max((similarity(form, their) for form in name_forms(muni, part, local)),
                default=0.0)
    ours = [t for t in tokens(local or part or without_district(muni)) if len(t) > 2]
    theirs = [t for t in tokens(candidate_name) if len(t) > 2]
    by_words = similarity("".join(sorted(ours)), "".join(sorted(theirs))) \
        if ours and theirs else 0.0
    return max(whole, by_words)


def distance_km(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(h))


def between(fraction, a, b):
    """A point on the straight line between two positions."""
    return (a[0] + (b[0] - a[0]) * fraction, a[1] + (b[1] - a[1]) * fraction)


def load_stage(name, default=None):
    path = os.path.join(WORK, name)
    if not os.path.exists(path):
        return {} if default is None else default
    try:
        with open(path) as fh:
            return json.load(fh)
    except ValueError:                        # a cache left half-written is no cache
        return {} if default is None else default


def save_stage(name, document):
    os.makedirs(WORK, exist_ok=True)
    path = os.path.join(WORK, name)
    with open(path, "w") as fh:
        json.dump(document, fh, ensure_ascii=False, sort_keys=True)
    print("  wrote %s" % os.path.relpath(path, REPO_ROOT), file=sys.stderr)
    return path


def read_rows(archive, name):
    """Rows of one of the fixed-width-ish JDF files, quotes and trailing ; removed."""
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


def ask_overpass(query):
    for endpoint in ("https://overpass-api.de/api/interpreter",
                     "https://overpass.kumi.systems/api/interpreter"):
        try:
            request = urllib.request.Request(
                endpoint,
                data=urllib.parse.urlencode({"data": query}).encode(),
                headers={"User-Agent": "vdv-live stop pipeline (one-off build step)"},
            )
            return json.loads(urllib.request.urlopen(request, timeout=300).read())["elements"]
        except Exception as error:            # noqa: BLE001 - try the next mirror
            print("  %s: %s" % (endpoint, error), file=sys.stderr)
    return []


def osm_position(element):
    """Where an Overpass element is: a node's own position or a way's centre."""
    lat = element.get("lat") or (element.get("center") or {}).get("lat")
    lon = element.get("lon") or (element.get("center") or {}).get("lon")
    return (lat, lon) if lat is not None and lon is not None else None


def index_by_normalised(elements):
    """Named elements grouped by folded name, e.g. all `Brtnice, náměstí` variants."""
    grouped = defaultdict(list)
    for element in elements:
        name = element.get("tags", {}).get("name")
        position = osm_position(element)
        if name and position:
            grouped[normalise(name)].append({"name": name, "lat": position[0], "lon": position[1]})
    return grouped


# A village is looked up by prefix as well as by name, because the timetables abbreviate
# and OpenStreetMap does not: "Jaroměřice n.Rok." against the node "Jaroměřice nad
# Rokytnou", "Kamenice n.Lipou" against "Kamenice nad Lipou". Without this, every stop in
# those towns looks as if it has no village at all.
VILLAGE_PREFIX_MIN = 6


def village_node(muni, part, places):
    """Where the stop's village is, allowing for an abbreviated town name."""
    for candidate in (without_district(muni), part):
        key = normalise(candidate or "")
        if not key:
            continue
        if key in places:
            return places[key]
        matches = [node for name, node in places.items()
                   if len(key) >= VILLAGE_PREFIX_MIN and name.startswith(key)]
        if matches:
            return min(matches, key=lambda node: len(node["name"]))
    return None

#!/usr/bin/env python3
"""Stage 3: the stops OpenStreetMap names exactly the way the timetable does.

A stop's name is tried in the forms a timetable prints it - "Municipality,Local",
"Municipality,Part,Local", "Municipality,Part", "Municipality" - after expanding the
abbreviations JDF uses and OpenStreetMap does not. The first form that exists wins.

One guard, learned the hard way: a *bare municipality* says nothing about which stop is
meant, so it is only accepted within `BARE_NAME_RADIUS_KM` of that municipality's own
place node. Without it, "Petrovice" matched a Petrovice forty kilometres away.

Usage: 03_match_direct.py
Reads stages 1 and 2, writes `build/stops/03_direct.json`.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

# A match on the municipality name alone has to be this close to the municipality.
BARE_NAME_RADIUS_KM = 15.0


def main():
    timetable = common.load_stage("01_timetable-stops.json")
    osm = common.load_stage("02_osm.json")
    if not timetable.get("stops") or not osm.get("stops"):
        raise SystemExit("stages 1 and 2 have to run first")

    by_name = common.index_by_normalised(osm["stops"])
    places = {key: candidates[0] for key, candidates in
              common.index_by_normalised(osm["places"]).items()}

    matched, unmatched = {}, []
    for key in timetable["stops"]:
        muni, part, local = common.split_key(key)
        base = common.without_district(muni)
        base_key = common.normalise(base)
        centre = common.village_node(muni, part, places)
        home = (centre["lat"], centre["lon"]) if centre else None

        for form in common.name_forms(muni, part, local):
            if form not in by_name:
                continue
            candidate = by_name[form][0]
            if form == base_key and home:
                if common.distance_km(home, (candidate["lat"], candidate["lon"])) > \
                        BARE_NAME_RADIUS_KM:
                    continue
            matched[key] = {
                "name": common.key_to_display(key),
                "latitude": round(candidate["lat"], 5),
                "longitude": round(candidate["lon"], 5),
                "match": "osm-name",
                "accuracyMetres": 40,
                "method": "direct: OpenStreetMap has \"%s\"" % candidate["name"],
            }
            break
        else:
            unmatched.append(key)

    common.save_stage("03_direct.json", {"matched": matched, "unmatched": unmatched})
    print("stage 3: %d of %d stops named exactly by OpenStreetMap (%d left)"
          % (len(matched), len(timetable["stops"]), len(unmatched)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Stage 4: the rest, matched by how the names line up rather than by being equal.

For each stop stage 3 could not place, the candidates are the OpenStreetMap stops around
the stop's *own village*: within `VILLAGE_RADIUS_KM` of the village's place node, or, when
there is no node, the stops whose name begins with the municipality's. Keeping the
candidates local is what stops a village of the same name in the next district answering
for this one.

Each candidate is scored on folded, expanded text: the better of the similarity of the
whole names and the similarity of the distinguishing parts. The best candidate is accepted
from `ACCEPT` up, and the score travels with the match so the decision is reviewable
rather than implied. Two kinds of match come out of this:

* `osm-village` - the candidate repeats the village and agrees with our local name
  (above `VILLAGE_AGREEMENT`), which is the "same village, same local name" case;
* `osm-similar` - no such agreement, but the names are close enough to be the same stop
  spelled differently.

Usage: 04_match_fuzzy.py
Reads stages 1-3, writes `build/stops/04_fuzzy.json`.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

VILLAGE_RADIUS_KM = 2.5          # how far from the village centre a stop may be
ACCEPT = 0.75                    # score at which a fuzzy match is believed
VILLAGE_AGREEMENT = 0.80         # score at which the distinguishing parts are "the same"


def score(our_muni, our_part, our_local, candidate_name):
    return common.score_names(our_muni, our_part, our_local, candidate_name)


def main():
    timetable = common.load_stage("01_timetable-stops.json")
    osm = common.load_stage("02_osm.json")
    direct = common.load_stage("03_direct.json")
    if not direct:
        raise SystemExit("stage 3 has to run first")

    stops_by_name = common.index_by_normalised(osm["stops"])
    places = {key: candidates[0] for key, candidates in
              common.index_by_normalised(osm["places"]).items()}
    all_stops = [stop for candidates in stops_by_name.values() for stop in candidates]

    matched, unmatched = {}, []
    for key in direct["unmatched"]:
        muni, part, local = common.split_key(key)
        base = common.without_district(muni)
        base_key = common.normalise(base)
        centre = common.village_node(muni, part, places)

        # The candidates: everything near the village, or, with no node, everything
        # whose name carries the village.
        if centre:
            home = (centre["lat"], centre["lon"])
            candidates = [stop for stop in all_stops
                          if common.distance_km(home, (stop["lat"], stop["lon"]))
                          <= VILLAGE_RADIUS_KM]
        else:
            candidates = [stop for candidates_at in stops_by_name.items()
                          if candidates_at[0].startswith(base_key)
                          for stop in candidates_at[1]]

        best, best_score = None, 0.0
        for candidate in candidates:
            candidate_score = score(muni, part, local, candidate["name"])
            if candidate_score > best_score:
                best, best_score = candidate, candidate_score

        if best is None or best_score < ACCEPT:
            unmatched.append(key)
            continue

        # "Same village, same local name" is worth saying differently from "close enough".
        repeats_village = common.normalise(best["name"]).startswith(base_key)
        kind = "osm-village" if (repeats_village and best_score >= VILLAGE_AGREEMENT) \
            else "osm-similar"
        matched[key] = {
            "name": common.key_to_display(key),
            "latitude": round(best["lat"], 5),
            "longitude": round(best["lon"], 5),
            "match": kind,
            "accuracyMetres": 150 if kind == "osm-village" else 250,
            "method": "%s: \"%s\" scored %.2f against %s"
                      % (kind, best["name"], best_score,
                         centre["name"] if centre else base),
        }

    common.save_stage("04_fuzzy.json",
                      {"matched": matched, "unmatched": unmatched,
                       "threshold": ACCEPT, "villageRadiusKm": VILLAGE_RADIUS_KM})
    print("stage 4: %d more stops matched (%d left over)"
          % (len(matched), len(unmatched)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Stage 5: everything that is known about the stops the first two passes could not place.

This stage places nothing. It writes the worklist that the next one reasons over, and that
a person can read when a placement is questioned. For each leftover stop:

* how the timetable spells it, and which district it is in;
* where its village is, if OpenStreetMap has a node for it;
* the stops already placed in that village, and their centre - usually the best answer,
  because it is derived from real stops rather than from a node;
* the stops either side of it on the lines that call at it, with their positions and the
  timetables' own distances, which is what makes a placement between them defensible;
* the villages within `NEARBY_RADIUS_KM` of all that, for a junction named after one;
* the OpenStreetMap candidates that were scored and rejected, with their scores, so a
  reader can see it was not a near-tie that went the wrong way.

Usage: 05_context.py
Reads stages 1-4, writes `build/stops/05_worklist.json`.
"""

import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

NEARBY_RADIUS_KM = 3.0
REJECTED_TO_KEEP = 3


def main():
    timetable = common.load_stage("01_timetable-stops.json")
    osm = common.load_stage("02_osm.json")
    direct = common.load_stage("03_direct.json")
    fuzzy = common.load_stage("04_fuzzy.json")

    placed = {}
    placed.update(direct.get("matched", {}))
    placed.update(fuzzy.get("matched", {}))
    if not placed:
        raise SystemExit("stages 3 and 4 have to run first")

    stops_by_name = common.index_by_normalised(osm["stops"])
    places = {key: candidates[0] for key, candidates in
              common.index_by_normalised(osm["places"]).items()}
    all_stops = [stop for candidates in stops_by_name.values() for stop in candidates]

    # Which lines call at a stop, and where it sits in them.
    unmatched = set(fuzzy.get("unmatched", []))
    lines_at = defaultdict(list)
    for entry, order in timetable["orders"].items():
        keys = [common.stop_key(*pieces) for pieces in order]
        for index, key in enumerate(keys):
            if key in unmatched:
                lines_at[key].append((entry, index, keys))

    def position_of(key):
        found = placed.get(key)
        return (found["latitude"], found["longitude"]) if found else None

    worklist = []
    for key in fuzzy.get("unmatched", []):
        muni, part, local = common.split_key(key)
        base = common.without_district(muni)
        base_key, part_key = common.normalise(base), common.normalise(part)

        # The village, and the stops already placed in it.
        centre = common.village_node(muni, part, places)
        in_village = [key_of_stop for key_of_stop in placed
                      if common.normalise(common.without_district(
                          common.split_key(key_of_stop)[0])) == base_key]
        village_positions = [position_of(k) for k in in_village]
        village_positions = [p for p in village_positions if p]

        # The stops either side of it, on the line where both are already placed.
        neighbours = []
        for entry, index, keys in lines_at.get(key, []):
            before = next(((position_of(keys[i]), keys[i], i)
                           for i in range(index - 1, -1, -1) if position_of(keys[i])), None)
            after = next(((position_of(keys[i]), keys[i], i)
                          for i in range(index + 1, len(keys)) if position_of(keys[i])), None)
            if before and after:
                neighbours.append({
                    "line": entry,
                    "before": common.key_to_display(before[1]),
                    "beforePosition": [round(before[0][0], 5), round(before[0][1], 5)],
                    "after": common.key_to_display(after[1]),
                    "afterPosition": [round(after[0][0], 5), round(after[0][1], 5)],
                    "kilometresApart": round(
                        common.distance_km(before[0], after[0]), 2),
                })

        # What the fuzzy pass scored and turned down.
        rejections = []
        if centre:
            home = (centre["lat"], centre["lon"])
            near = [(common.score_names(muni, part, local, stop["name"]), stop)
                    for stop in all_stops
                    if common.distance_km(home, (stop["lat"], stop["lon"])) <= NEARBY_RADIUS_KM]
            near.sort(key=lambda pair: -pair[0])
            rejections = [{"name": stop["name"], "score": round(value, 2)}
                          for value, stop in near[:REJECTED_TO_KEEP]]

        worklist.append({
            "key": key,
            "name": common.key_to_display(key),
            "district": timetable["stops"][key]["district"],
            "villageCentre": ({"name": centre["name"],
                               "position": [round(centre["lat"], 5), round(centre["lon"], 5)]}
                              if centre else None),
            "placedInVillage": {"count": len(village_positions),
                                "centre": ([round(sum(p[0] for p in village_positions)
                                                  / len(village_positions), 5),
                                            round(sum(p[1] for p in village_positions)
                                                  / len(village_positions), 5)]
                                           if village_positions else None)},
            "neighbours": neighbours[:3],
            "nearbyPlaces": [{"name": node["name"],
                              "position": [round(node["lat"], 5), round(node["lon"], 5)]}
                             for key_at_node, node in places.items()
                             if centre and common.distance_km(
                                 (centre["lat"], centre["lon"]),
                                 (node["lat"], node["lon"])) <= NEARBY_RADIUS_KM][:8],
            "rejectedCandidates": rejections,
        })

    common.save_stage("05_worklist.json",
                      {"worklist": worklist, "nearbyRadiusKm": NEARBY_RADIUS_KM})
    print("stage 5: %d stops need placing" % len(worklist), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

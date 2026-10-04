#!/usr/bin/env python3
"""Stage 6: placing what is left, by rule, with the reasoning written down.

Nothing here is a name match. These are placements reasoned from context, tried in the
order they can be trusted, and every one carries the rule that produced it so a reader can
disagree with the rule rather than with a number:

1. `manual` - a placement written by hand in `data/manual_matches.json`, keyed by the name
   the app shows. These beat everything else and are how a stop that needs a person's eye
   gets one.
2. `village-centroid` - the stop's village already has stops placed in it, so this one is
   near their centre. Better than the village node because it is derived from real stops.
3. `named-near` - the stop is named after a street, a shop or a factory rather than a
   village, so its name is matched against the OpenStreetMap stops that lie near the line
   it is on: near the two stops either side of it, or near any stop of the same line that
   already has a position. The name picks out the stop, the line says which town.
4. `village-centre` - the village has a node in OpenStreetMap but no placed stop: the stop
   is somewhere in the village, and that is as much as can honestly be said.
5. `route` - a placed stop either side of it on a line, and the line's own distances
   usable: the position is on the straight line between them, at the fraction their
   distances give. Low confidence, because roads bend.
6. Anything else is left for review rather than guessed at.

Usage: 06_place_by_rule.py
Reads stages 1, 3, 4 and 5, writes `build/stops/06_placed.json`.
"""

import json
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

# The neighbours have to be this close for a point between them to mean anything.
ROUTE_MAX_KM = 15.0
# How far from the middle of those neighbours a street or landmark name may be found.
URBAN_RADIUS_KM = 4.0
# How far from an already placed stop of the same line such a name may be found. Tighter
# than the neighbour midpoint, because a line is long and its stops are many.
LINE_RADIUS_KM = 2.0


def main():
    timetable = common.load_stage("01_timetable-stops.json")
    direct = common.load_stage("03_direct.json")
    fuzzy = common.load_stage("04_fuzzy.json")
    worklist = common.load_stage("05_worklist.json").get("worklist", [])
    if not worklist:
        raise SystemExit("stage 5 has to run first")

    known = {}
    known.update(direct.get("matched", {}))
    known.update(fuzzy.get("matched", {}))
    positions = {key: (row["latitude"], row["longitude"]) for key, row in known.items()}

    manual = {}
    if os.path.exists(common.MANUAL):
        manual = {common.key_of(name): row
                  for name, row in json.load(open(common.MANUAL)).items()
                  if not name.startswith("_")}

    # Every stop OpenStreetMap has, with its name in words, for the urban-name rule.
    every_osm_stop = []
    for element in common.load_stage("02_osm.json").get("stops", []):
        stop_name = element.get("tags", {}).get("name")
        position = common.osm_position(element)
        if stop_name and position:
            every_osm_stop.append({"name": stop_name, "lat": position[0], "lon": position[1],
                                   "words": set(common.tokens(stop_name))})

    # Which lines call at which stops, the other way round, so an unplaceable stop can be
    # anchored to the line it is on and not only to the two stops either side of it.
    lines_at = defaultdict(list)
    for entry, order in timetable.get("orders", {}).items():
        for pieces in order:
            lines_at[common.stop_key(*pieces)].append(entry)

    # Where each stop sits in each line, so its neighbours can be found.
    runs_at = defaultdict(list)
    for entry, run in timetable.get("runs", {}).items():
        for index, (pieces, distance) in enumerate(run):
            runs_at[common.stop_key(*pieces)].append((entry, index, run))

    placed, unplaced = {}, []
    for item in worklist:
        key = item["key"]
        name = item["name"]

        if common.key_of(name) in manual:
            row = manual[common.key_of(name)]
            placed[key] = {
                "name": name, "latitude": row["latitude"], "longitude": row["longitude"],
                "match": "place", "accuracyMetres": row.get("accuracyMetres", 300),
                "method": "manual: %s" % row.get("method", "placed by hand"),
            }
            positions[key] = (placed[key]["latitude"], placed[key]["longitude"])
            continue

        village = item.get("placedInVillage") or {}
        if village.get("count", 0) > 0 and village.get("centre"):
            latitude, longitude = village["centre"]
            placed[key] = {
                "name": name, "latitude": latitude, "longitude": longitude,
                "match": "place", "accuracyMetres": 300,
                "method": "village-centroid: centre of the %d stops already placed in %s"
                          % (village["count"], common.without_district(
                              common.split_key(key)[0])),
            }
            positions[key] = (latitude, longitude)
            continue

        # A stop named after a street, a shop or a factory inside a town - JDF puts the
        # landmark in the municipality column for those - has no village to anchor at.
        # Its name is matched against the OpenStreetMap stops that lie near the line it is
        # on, which is what makes this safe: the name picks out the stop and the line says
        # which town it can possibly be in. Two kinds of anchor are tried, because they
        # fail in different places: the middle of the two stops either side of this one,
        # and every stop of the same line that already has a position. This has to be
        # tried before the village centre, because a stop found by name is a better answer
        # than the middle of its village.
        ours = {word for word in common.tokens(name) if len(word) > 3}
        anchors = []
        for neighbour in item.get("neighbours", []):
            before, after = neighbour["beforePosition"], neighbour["afterPosition"]
            anchors.append((((before[0] + after[0]) / 2, (before[1] + after[1]) / 2),
                            URBAN_RADIUS_KM, "the middle of %s and %s"
                            % (neighbour["before"], neighbour["after"])))
        for entry in lines_at.get(key, ()):
            for pieces in timetable.get("orders", {}).get(entry, ()):
                other = common.stop_key(*pieces)
                if other != key and other in positions:
                    anchors.append((positions[other], LINE_RADIUS_KM,
                                    "%s on line %s" % (common.key_to_display(other), entry)))

        named = None
        if ours:
            for candidate in every_osm_stop:
                if not ours.issubset(candidate["words"]):
                    continue
                for position, radius, description in anchors:
                    apart = common.distance_km(position, (candidate["lat"], candidate["lon"]))
                    if apart <= radius and (named is None or apart < named[0]):
                        named = (apart, candidate, description)
        if named:
            apart, candidate, description = named
            placed[key] = {
                "name": name, "latitude": round(candidate["lat"], 5),
                "longitude": round(candidate["lon"], 5),
                "match": "osm-similar", "accuracyMetres": 200,
                "method": "named-near: OpenStreetMap has \"%s\", %.1f km from %s"
                          % (candidate["name"], apart, description),
            }
            positions[key] = (placed[key]["latitude"], placed[key]["longitude"])
            continue

        if item.get("villageCentre"):
            latitude, longitude = item["villageCentre"]["position"]
            placed[key] = {
                "name": name, "latitude": latitude, "longitude": longitude,
                "match": "place", "accuracyMetres": 600,
                "method": "village-centre: OpenStreetMap's node for %s, no stop of this "
                          "name found" % item["villageCentre"]["name"],
            }
            continue

        # Between the two stops of a line this one sits between, by the timetable's own
        # distances. Only where those distances run one way, which they do not on a loop.
        best = None
        for entry, index, run in runs_at.get(key, []):
            distances = [distance for _pieces, distance in run]
            if distances != sorted(distances):
                continue
            before = next(((i, run[i]) for i in range(index - 1, -1, -1)
                           if common.stop_key(*run[i][0]) in positions), None)
            after = next(((i, run[i]) for i in range(index + 1, len(run))
                          if common.stop_key(*run[i][0]) in positions), None)
            if not before or not after:
                continue
            before_position = positions[common.stop_key(*before[1][0])]
            after_position = positions[common.stop_key(*after[1][0])]
            span = common.distance_km(before_position, after_position)
            if span > ROUTE_MAX_KM or span <= 0.05:
                continue
            distance_span = run[after[0]][1] - run[before[0]][1]
            if distance_span <= 0:
                continue
            fraction = (run[index][1] - run[before[0]][1]) / distance_span
            if not 0 < fraction < 1:
                continue
            candidate = (span, fraction, before_position, after_position,
                         common.key_to_display(common.stop_key(*before[1][0])),
                         common.key_to_display(common.stop_key(*after[1][0])))
            if best is None or candidate[0] < best[0]:
                best = candidate

        if best:
            span, fraction, before_position, after_position, before_name, after_name = best
            latitude, longitude = common.between(fraction, before_position, after_position)
            placed[key] = {
                "name": name, "latitude": round(latitude, 5), "longitude": round(longitude, 5),
                "match": "route", "accuracyMetres": 800,
                "method": "route: %.0f%% of the way from %s to %s on the same line"
                          % (fraction * 100, before_name, after_name),
            }
            positions[key] = (placed[key]["latitude"], placed[key]["longitude"])
            continue

        unplaced.append(item)

    common.save_stage("06_placed.json", {"placed": placed, "unplaced": unplaced})
    print("stage 6: placed %d by rule, %d still need a person"
          % (len(placed), len(unplaced)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

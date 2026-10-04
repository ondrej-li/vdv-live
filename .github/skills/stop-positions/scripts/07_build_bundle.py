#!/usr/bin/env python3
"""Stage 7: judge every position against the timetable, then write what ships.

Two guards, in the order of how much they can be trusted:

* **isolation** - a position more than `ISOLATION_KM` from every other stop its line calls
  at is wrong. A bus does not serve one stop twenty kilometres from the rest of its route.
  This is what catches a village of the same name being answered by its namesake.
* **the timetables' own distances** - two neighbouring calls cannot straight-line further
  than `DISTANCE_SLACK` times their distance apart, plus `DISTANCE_FLOOR_KM`. The distance
  column counts *down* to the end of the run, so on a route that loops back it is not
  monotone and means nothing: those runs are skipped rather than trusted.

A position that fails a guard is not published. It goes to `docs/stop-review.md` with the
rest of what is questionable, which is where a person looks rather than at a script.

What ships is one row per name the app can show: where it is, how it was arrived at, and
how close it is likely to be. Nothing else - the reasoning lives in the stage files and
the review.

Usage: 07_build_bundle.py
Reads stages 1, 3, 4 and 6, writes `VdvLive/Resources/stop-positions.json` and
`docs/stop-review.md`.
"""

import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

ISOLATION_KM = 12.0
DISTANCE_SLACK, DISTANCE_FLOOR_KM = 1.6, 3.0
# Kinds that are placements rather than name matches, and so always worth a look.
WEAK = {"place", "route"}
# Kinds that claim to be the stop itself. The distance budget only judges between these:
# a village centre is coarse by design, and letting it testify against its neighbour
# turned a few hundred coarse placements into a few hundred rejections.
PRECISE = {"osm-name", "osm-village", "osm-similar", "osm-near"}
# Two stops with one display name further apart than this are different places, and the
# app cannot tell them apart, so neither is shipped.
CLASH_KM = 5.0


def main():
    timetable = common.load_stage("01_timetable-stops.json")
    direct = common.load_stage("03_direct.json")
    fuzzy = common.load_stage("04_fuzzy.json")
    by_rule = common.load_stage("06_placed.json")
    if not direct:
        raise SystemExit("the earlier stages have to run first")

    candidates = {}
    candidates.update(direct.get("matched", {}))
    candidates.update(fuzzy.get("matched", {}))
    candidates.update(by_rule.get("placed", {}))
    positions = {key: (row["latitude"], row["longitude"]) for key, row in candidates.items()}

    flagged, looping = set(), 0
    for entry, order in timetable.get("orders", {}).items():
        keys = [common.stop_key(*pieces) for pieces in order]
        known = [(key, positions[key]) for key in keys if key in positions]
        if len(known) < 3:
            continue
        for key, position in known:
            others = [other for other_key, other in known if other_key != key]
            if all(common.distance_km(position, other) > ISOLATION_KM for other in others):
                flagged.add(key)

    for entry, run in timetable.get("runs", {}).items():
        distances = [distance for _pieces, distance in run]
        if distances != sorted(distances):
            looping += 1
            continue
        for step in range(1, len(run)):
            before = common.stop_key(*run[step - 1][0])
            after = common.stop_key(*run[step][0])
            if before not in positions or after not in positions:
                continue
            if candidates[before]["match"] not in PRECISE \
                    or candidates[after]["match"] not in PRECISE:
                continue
            allowed = max(DISTANCE_SLACK * abs(run[step][1] - run[step - 1][1]),
                          DISTANCE_FLOOR_KM)
            if common.distance_km(positions[before], positions[after]) > allowed:
                flagged.add(before)
                flagged.add(after)

    table, kinds, clashes = {}, Counter(), defaultdict(list)
    for key, row in candidates.items():
        if key in flagged:
            continue
        lookup = common.key_of(row["name"])
        entry = {"name": row["name"], "latitude": row["latitude"], "longitude": row["longitude"],
                 "match": row["match"], "accuracyMetres": row["accuracyMetres"]}
        existing = table.get(lookup)
        if existing:
            apart = common.distance_km((existing["latitude"], existing["longitude"]),
                                       (entry["latitude"], entry["longitude"]))
            clashes[lookup].append(key)
            if apart > CLASH_KM:
                # Two villages, one display name, and the app looks a stop up by that name
                # alone: it would put this position on both of them. Showing nothing is
                # better than being half wrong, so the name goes to the review instead.
                table.pop(lookup, None)
                continue
            # The same stop twice, or two namesakes inside one village: either will do,
            # so keep whichever position we trust more.
            if (entry["accuracyMetres"] or 10_000) < (existing["accuracyMetres"] or 10_000):
                table[lookup] = entry
            continue
        table[lookup] = entry
        kinds[row["match"]] += 1

    document = {
        "version": 1,
        "note": "Stop positions for the region's timetables, from OpenStreetMap by name "
                "where possible and by rule where not. See docs/stops.md.",
        "sources": [{"name": "OpenStreetMap", "licence": "ODbL 1.0",
                     "url": "https://www.openstreetmap.org/copyright"}],
        "stops": dict(sorted(table.items())),
    }
    os.makedirs(os.path.dirname(common.BUNDLE), exist_ok=True)
    with open(common.BUNDLE, "w") as fh:
        json.dump(document, fh, ensure_ascii=False, separators=(",", ":"))

    write_review(candidates, flagged, by_rule.get("unplaced", []), table, clashes)

    print()
    print("region stops:            %6d" % len(timetable.get("stops", {})))
    for kind in ("osm-name", "osm-village", "osm-similar", "place", "route"):
        print("  %-16s %6d" % (kind, kinds[kind]))
    print("  %-16s %6d" % ("dropped by guards", len(flagged)))
    print("  %-16s %6d" % ("unplaced", len(by_rule.get("unplaced", []))))
    dropped_names = [name for name in clashes if name not in table]
    print("shipped rows:            %6d  (names shared by more than one stop: %d, of "
          "which shipped none: %d; looping runs skipped: %d)"
          % (len(table), len(clashes), len(dropped_names), looping))
    print("wrote %s (%.0f KB)" % (os.path.relpath(common.BUNDLE, common.REPO_ROOT),
                                  os.path.getsize(common.BUNDLE) / 1024))
    return 0


def write_review(candidates, flagged, unplaced, table, clashes):
    """What a person should look at: nothing placed, and everything placed by a rule."""
    unplaced_lines = []
    for item in unplaced:
        village = (item.get("villageCentre") or {}).get("name", "")
        centre = (item.get("placedInVillage") or {}).get("count", 0)
        unplaced_lines.append("| %s | %s | %s | stops placed in the village: %d |"
                              % (item["name"], item.get("district", ""), village or "-", centre))

    weak_lines = []
    for key, row in sorted(candidates.items(), key=lambda pair: pair[1]["name"]):
        if row["match"] not in WEAK or common.key_of(row["name"]) not in table:
            continue
        weak_lines.append("| %s | %s | %.5f, %.5f | %s |"
                          % (row["name"], row["match"], row["latitude"], row["longitude"],
                             row.get("method", "")))

    dropped_lines = []
    for key in sorted(flagged):
        row = candidates.get(key)
        if row and common.key_of(row["name"]) not in table:
            dropped_lines.append("| %s | %s | %s |"
                                 % (row["name"], row["match"], row.get("method", "")))

    # A name that had to be dropped because two villages answer to it: the app looks a
    # stop up by the name alone, so one position would have been put on both of them.
    same_name_lines = []
    for lookup in sorted(clashes):
        if lookup in table:
            continue
        for key in clashes[lookup]:
            row = candidates.get(key)
            if row:
                same_name_lines.append("| %s | %s | %s | %.5f, %.5f |"
                                       % (row["name"], row["match"],
                                          (row.get("method") or "")[:110],
                                          row["latitude"], row["longitude"]))

    with open(common.REVIEW, "w") as fh:
        fh.write("# Stops still to be checked\n\n")
        fh.write("Written by `.github/skills/stop-positions/scripts/07_build_bundle.py`; "
                 "regenerate with `make stops`. Everything here is either not placed at "
                 "all or placed by a rule rather than by a name, so it is the part of the "
                 "table that deserves an eye. Corrections go in "
                 "`.github/skills/stop-positions/data/manual_matches.json`, which wins "
                 "over every rule.\n\n")
        fh.write("Placed by name and left alone: %d of %d rows.\n\n"
                 % (sum(1 for row in table.values() if row["match"] in PRECISE),
                    len(table)))
        fh.write("## Not placed at all (%d)\n\n" % len(unplaced_lines))
        fh.write("| Stop | District | Village | Context |\n|---|---|---|---|\n")
        fh.write("\n".join(unplaced_lines) or "| - | - | - | - |")
        fh.write("\n\n## Placed by a rule, not by a name match (%d)\n\n" % len(weak_lines))
        fh.write("| Stop | Kind | Position | Why |\n|---|---|---|---|\n")
        fh.write("\n".join(weak_lines) or "| - | - | - | - |")
        fh.write("\n\n## Dropped by the guards (%d)\n\n" % len(dropped_lines))
        fh.write("A position the timetable says cannot be right: too far from every other "
                 "stop of its line, or further from its neighbour than the route between "
                 "them allows.\n\n")
        fh.write("| Stop | Was matched as | Why it was thought to be there |\n|---|---|---|\n")
        fh.write("\n".join(dropped_lines) or "| - | - | - |")
        fh.write("\n\n## Dropped because two places answer to the name (%d)\n\n"
                 % len(same_name_lines))
        fh.write("The app looks a stop up by its display name alone, so a position for "
                 "one of these would have been shown for the other as well. Both are "
                 "withheld until a person says which is which.\n\n")
        fh.write("| Stop | Kind | Why it was thought to be there | Position |\n"
                 "|---|---|---|---|\n")
        fh.write("\n".join(same_name_lines) or "| - | - | - | - |")
        fh.write("\n")
    print("  wrote %s" % os.path.relpath(common.REVIEW, common.REPO_ROOT), file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())

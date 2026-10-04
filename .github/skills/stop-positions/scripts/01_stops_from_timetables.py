#!/usr/bin/env python3
"""Stage 1: every stop the timetables mention, and how each line calls at them.

Reads the national JDF archive and keeps the stops whose district is one of the
Vysocina Region's five. Writes three things:

* `stops`  - the region's stops, keyed by municipality/part/local name.
* `orders` - for each line, the order it calls at its stops.
* `runs`   - for each line, one representative run: stop by stop, with the distance
             column the timetable carries. That column counts down to the end of the
             run, which matters in stage 7 (see `SKILL.md`).

Usage: 01_stops_from_timetables.py [archive]

The archive is the same one the app reads; `make stops` downloads it when it is missing.
Its parse is cached in `build/stops/`, and `REFRESH_JDF=1` redoes it.
"""

import io
import os
import sys
import zipfile
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402


def main():
    archive_path = sys.argv[1] if len(sys.argv) > 1 else common.ARCHIVE
    if not os.path.exists(archive_path):
        raise SystemExit("no archive at %s - run `make stops` to fetch it" % archive_path)

    cache = os.path.join(common.WORK, "01_timetable-stops.json")
    if os.path.exists(cache) and os.environ.get("REFRESH_JDF") != "1":
        document = common.load_stage("01_timetable-stops.json")
        if document.get("stops"):
            print("stage 1: using the cached archive parse (%d stops)" % len(document["stops"]),
                  file=sys.stderr)
            return 0

    stops, orders, runs = {}, {}, {}
    with zipfile.ZipFile(archive_path) as outer:
        names = [n for n in outer.namelist() if n.lower().endswith(".zip")]
        for index, entry in enumerate(names):
            with zipfile.ZipFile(io.BytesIO(outer.read(entry))) as inner:
                table, in_region = {}, False
                for row in common.read_rows(inner, "Zastavky.txt"):
                    if len(row) < 6:
                        continue
                    table[row[0]] = (row[1], row[2], row[3])
                    if row[4] in common.REGION:
                        in_region = True
                        key = common.stop_key(row[1], row[2], row[3])
                        stops.setdefault(key, {"district": row[4]})
                if not in_region:
                    continue

                orders[entry] = [list(table[row[3]])
                                 for row in common.read_rows(inner, "Zaslinky.txt")
                                 if len(row) > 3 and row[3] in table]

                # One run per line is enough to judge whether two positions could be
                # reached from one another: take the run the timetable is most complete for.
                collected = defaultdict(list)
                for row in common.read_rows(inner, "Zasspoje.txt"):
                    if len(row) <= common.COL_DISTANCE or row[common.COL_STOP] not in table:
                        continue
                    distance = row[common.COL_DISTANCE].strip()
                    if distance.isdigit():
                        collected[row[common.COL_SERVICE]].append(
                            [list(table[row[common.COL_STOP]]), int(distance)])
                best = max(collected.values(), key=len, default=[])
                if len(best) > 1:
                    runs[entry] = best
            if index % 2000 == 0:
                print("  archive %d/%d" % (index, len(names)), file=sys.stderr)

    common.save_stage("01_timetable-stops.json",
                      {"stops": stops, "orders": orders, "runs": runs})
    print("stage 1: %d stops, %d lines, %d runs with distances"
          % (len(stops), len(orders), len(runs)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/bin/sh
# The whole stop pipeline, in order. `make stops` calls this, and `SKILL.md` explains
# what each stage does and which environment variables force a cache to be redone.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
for stage in 01_stops_from_timetables 02_stops_from_osm 03_match_direct 04_match_fuzzy \
             05_context 06_place_by_rule 07_build_bundle; do
    echo "== $stage"
    python3 "$here/$stage.py" "$@"
done

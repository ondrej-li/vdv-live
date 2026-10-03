---
name: stop-positions
description: 'Place bus stops on the map and keep the shipped stop-position table current. USE FOR: drawing stops or stop names on the map; regenerating or extending the stop-position bundle; fixing stop-name matching (abbreviations, hamlet names, village fallback); checking coverage or explaining why a stop has no position; answering whether a data source publishes stop coordinates at all. DO NOT USE FOR: parsing timetables (read docs/timetables.md), map rendering itself, or the live vehicle feed.'
---

# Stop positions

Where the region's stops are, and how to keep that table honest. Read
[docs/stops.md](../../docs/stops.md) for the measurements behind every claim here; this
file is the procedure.

## The one thing to know first

**No timetable source publishes stop coordinates.** JDF's `Zastavky.txt` has no coordinate
columns at all (its columns 7-12 are tariff zones), and the ministry's NeTEx export has
309,789 `StopPlace`s and 327,110 `ScheduledStopPoint`s with every `<Location />` empty. The
live feed has positions for *vehicles* only, and the region publishes no transport data.

Positions therefore come from **OpenStreetMap**, matched **by stop name**, which is why
every rule below exists. Matching is the whole problem; treat every new match as a
hypothesis until the timetable agrees with it.

| Source | Names | Positions |
|---|---|---|
| JDF archive (what the app ships) | yes | no |
| NeTEx export (same ministry) | yes | no |
| Live feed (`mapavdv`) | current stop only | vehicles only |
| Kraj Vysočina open data | nothing transport | — |
| ČÚZK ZABAGED | rail | rail |
| **OpenStreetMap** | yes | **yes** |

## Regenerating the table

```sh
make stops                     # downloads the JDF archive if needed, then:
python3 tools/stop_positions.py /tmp/jdf/JDF.zip VdvLive/Resources/stop-positions.json
```

The archive is republished a few times a week, so run it before a release, and commit the
resulting `VdvLive/Resources/stop-positions.json`. Parsing the archive and asking
OpenStreetMap are both cached under `build/stops/`; `REFRESH_JDF=1` or
`REFRESH_OSM=1` forces either one to be redone.

## How the pipeline works, in order

1. **Region stops** — read every line in the archive, keep the stops whose JDF district is
   one of JI, TR, PE, HB, ZR. That is the list to place (about 3,500 stops, ~2,600 distinct
   display names).
2. **Line order and distances** — from `Zaslinky.txt` and one representative run of
   `Zasspoje.txt` (distance is column 9). This is what makes step 5 possible.
3. **OpenStreetMap** — stops inside the region's *administrative boundary* (never a
   bounding box: a village with a common name must not be answered by its namesake next
   door), plus village centres.
4. **Matching**, most to least specific, each result tagged with its kind and accuracy:
   - `osm-name` (40 m) — the stop's name in the forms a timetable prints, after expanding
     JDF's abbreviations (`nám.`→`náměstí`, `rozc.`→`rozcestí`, `aut.nádr.`→`autobusové nádraží`).
   - `osm-village` (150 m) — OSM name starts with the village and carries our local name.
   - `osm-near` (250 m) — a stop named after a hamlet, filed in OSM under the hamlet alone;
     only accepted within 5 km of the village.
   - `place` (600 m) — the village centre. **Not written to the shipped file** unless
     `--include-village-centres` is passed: it is within a few hundred metres of everything
     in that village, which for a dot with a stop's name on it is a guess.
   - A bare village name is only accepted within 15 km of that village.
5. **Two guards judge the result**, and a position that fails is dropped (never guessed):
   - *Isolation*: a position more than 12 km from every other stop its line calls at is
     wrong. This is the primary guard and catches the gross errors.
   - *The timetable's own distances*: two neighbouring calls cannot straight-line further
     than 1.6× their distance apart in the timetable, plus 3 km. **The distance column
     counts down to the end of the run**, so on a route that loops back it is not monotone
     and the difference between two calls means nothing — those runs are skipped, not used
     to reject good positions. Skipping them rather than trusting them is what stopped a
     third of the table from being thrown away.

## Where they are shown

The map draws them behind a preference - **Settings ▸ Preferences ▸ Stops ▸ "Show stops on the map"**, off by default - and `VehicleMapViewModel.stopFlags` decides what that means: only the stops inside the viewport, and only once the map is zoomed in past `stopFlagsSpanMetres` (15 km across). At region zoom there are over a thousand known stops and drawing them covers the map. `StopPositions.positions(latitude:longitude:)` is the filter, `StopAnnotationView` is the flag, and the table is only read the first time the option is on.

## Judging a change

Numbers to look at (the script prints them) and what they should look like:

| Reading | Healthy |
|---|---|
| `osm-name` | ~52% of region stops — the biggest lever is the abbreviation table |
| `osm-name` + `osm-village` + `osm-near` | ~62% of region stops |
| positions rejected | low hundreds, not thousands |
| published entries | ~1,800, and name clashes should stay exotic |

Red flags, in the order they have actually bitten:

- **A position far from its village.** If you see this, check the OSM query is
  area-scoped and that the bare-name radius is applied. A bounding box pulled in neighbouring
  regions and produced positions 90 km out.
- **Long hops between adjacent stops.** Means the distance budget is not running — check the
  archive cache actually captured distances (`runs with distances:` should not be 0).
- **Mass rejections after touching a guard.** If a guard rejects a third of the table, it is
  probably reading the distance column on looping runs; check the `runs skipped as looping`
  count is in the hundreds, not zero.
- **A good match missing.** Two stops can share one display name once the district suffix is
  stripped; keep the more accurate of the two, never drop the name.
- **Coverage dropping after an "improvement".** Matching is greedy: a new tier tried too early
  steals stops from a better one. Order the tiers by specificity.

## Do not

- Do not try to mine stop positions from the feed at scale: the last stop name only exists in
  `OpenInfoWindow` (one request per vehicle), so covering the region would mean thousands of
  requests against a site the app depends on.
- Do not publish a position whose only evidence is a name match with no distinguishing part.
- Do not add OpenStreetMap-derived data without attribution: the table is ODbL, and the
  credits screen has to say so.

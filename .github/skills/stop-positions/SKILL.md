---
name: stop-positions
description: 'Place bus stops on the map and keep the shipped stop-position table current. USE FOR: drawing stops or stop names on the map; regenerating or extending the stop-position bundle; fixing stop-name matching (abbreviations, hamlet names, village fallback); placing a stop the pipeline could not locate; checking coverage or explaining why a stop has no position; answering whether a data source publishes stop coordinates at all. DO NOT USE FOR: parsing timetables (read docs/timetables.md), map rendering itself, or the live vehicle feed.'
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
make stops                        # every stage in order; stages 1 and 2 are cached
```

The archive is republished a few times a week, so run it before a release, and commit the
resulting `VdvLive/Resources/stop-positions.json`. Parsing the archive and asking
OpenStreetMap are both cached under `build/stops/`; `REFRESH_JDF=1` or `REFRESH_OSM=1`
forces either one to be redone. `JDF_ARCHIVE=/tmp/JDF.zip` skips the download.

The scripts are in `scripts/`, one per stage, run in numeric order by `run_all.sh`. Each
reads the stage before it and writes its own JSON into `build/stops/`, so a stage can be
re-run on its own - which is what you do after touching a rule, rather than starting over.

| Stage | Script | Reads | Writes |
|---|---|---|---|
| 1 | `01_stops_from_timetables.py` | the JDF archive | `01_timetable-stops.json` |
| 2 | `02_stops_from_osm.py` | Overpass | `02_osm.json` |
| 3 | `03_match_direct.py` | 1, 2 | `03_direct.json` |
| 4 | `04_match_fuzzy.py` | 1, 2, 3 | `04_fuzzy.json` |
| 5 | `05_context.py` | 1, 2, 3, 4 | `05_worklist.json` |
| 6 | `06_place_by_rule.py` | 1, 2, 3, 4, 5 | `06_placed.json` |
| 7 | `07_build_bundle.py` | 1, 3, 4, 6 | the shipped bundle, `docs/stop-review.md` |

`scripts/common.py` holds what they share: the region, the abbreviation table, the name
normalisation and the fold that has to agree with the app (`key_of`), the distance maths,
the Overpass client and the stage-file helpers.

## How the pipeline works, in order

**1. Every stop the timetables name.** Read the archive, keep the stops whose JDF district
is one of JI, TR, PE, HB, ZR: about 3,500 stops and 1,000 lines today. For each line keep
its calling order and one representative run with the timetable's own distances; those
distances are what stage 6 uses.

**2. Every stop and place OpenStreetMap has.** Two cached Overpass queries inside
`REGION_BBOX`: stop-like elements (`highway=bus_stop`, `public_transport=stop_position`,
platforms) and place nodes (city, town, village, hamlet, suburb). A failed query never
gets written over a good cache.

**3. Direct matches.** The stop's name against the OpenStreetMap names, both folded the
same way, with JDF's abbreviations expanded first. A bare village name is only believed
within 15 km of that village, because "Petrovice" exists many times.

**4. Fuzzy matches.** Two forms, each with a score threshold and a radius: the same local
name in the same village, and a name whose words are close enough to ours. The village
lookup accepts a prefix, so `Jaroměřice n.Rok.` finds `Jaroměřice nad Rokytnou`.

**5. Context for what is left.** For every stop still unplaced, gather what a person would
want: the village's OpenStreetMap node, the centre of the stops already placed in that
village, the stops either side of it on its line, the places nearby, and the candidates
that were rejected, with their scores. This stage decides nothing; it is the dossier.

**6. Placement by rule**, tried in the order the rules can be trusted. Every row carries
the rule that made it, in words, so a reader can disagree with the rule rather than with a
number:

| Rule | Match kind | Accuracy | What it says |
|---|---|---|---|
| `manual` | `place` | as written | a row in `data/manual_matches.json`, written by a person |
| `village-centroid` | `place` | 300 m | centre of the stops already placed in this village |
| `named-near` | `osm-similar` | 200 m | an OpenStreetMap stop whose name contains ours, near the middle of the two stops either side of this one, or near any stop of the same line that already has a position |
| `village-centre` | `place` | 600 m | the village's own OpenStreetMap node |
| `route` | `route` | 800 m | on the straight line between the two placed stops either side, at the fraction their timetable distances give |

Anything the rules cannot justify is **left unplaced and written to the review**, never
guessed at. The `named-near` rule is what places stops JDF names after a street, a shop or
a factory (`Barum`, `Husova`, `KD Ostrov`, `Psych.nemocnice`): the name picks out the stop
and the line says which town, which is the only handle those stops have.

**7. The bundle and the review.** The guards run, the rows are keyed by display name and
written out, and `docs/stop-review.md` is generated. Four guards, each added because the
join got it wrong:

- *Isolation*: a position more than 12 km from every other stop its line calls at is
  dropped. This is the primary guard, and it is what removed the 90 km matches.
- *Distances*: two neighbouring calls cannot straight-line further than 1.6x their
  timetable distance plus 3 km. **The distance column counts down to the end of the run**,
  so on a looping route the difference between two calls means nothing: those runs are
  skipped (about 440 of 1,000), not used to reject correct positions. Only name-level
  matches testify here, since a village centre is coarse by design.
- *Namesakes*: two stops with one display name more than 5 km apart are both withheld. The
  app looks a stop up by name alone, so one position would have been shown for both.
- *Nothing else*: no position is invented to fill a gap.

## The review file, and what to do with it

`docs/stop-review.md` is written by stage 7 and has three parts: stops not placed at all,
stops placed by a rule rather than by a name, and stops dropped by the guards. It is the
honest inventory of what is weak, so commit it with the bundle.

A correction goes in `data/manual_matches.json`, keyed by the display name the app shows,
with `latitude`, `longitude`, `accuracyMetres` and a `method` saying why. It wins over every
rule, and the `method` travels into the shipped row. Use
`build/stops/05_worklist.json` for the evidence: it holds the neighbours, the village node,
the candidates and the rejected scores for each leftover stop.

## Where they are shown

The map draws them behind a preference - **Settings ▸ Preferences ▸ Stops ▸ "Show stops on the map"**, off by default - and `VehicleMapViewModel.stopFlags` decides what that means: only the stops inside the viewport, and only once the map is zoomed in past `stopFlagsSpanMetres` (15 km across). At region zoom there are over a thousand known stops and drawing them covers the map. `StopPositions.positions(latitude:longitude:)` is the filter, `StopAnnotationView` is the flag, and the table is only read the first time the option is on.

## Judging a change

The last stage prints this, and what a healthy run looks like today:

```
region stops:              3521
  osm-name           1486
  osm-village         218
  osm-similar         240
  place               580
  route                 4
  dropped by guards    371
  unplaced             17
shipped rows:              2527
```

| Reading | Healthy |
|---|---|
| `osm-name` + `osm-village` + `osm-similar` + `osm-near` | roughly 1,950 rows; the biggest lever is the abbreviation table |
| `dropped by guards` | a few hundred, not thousands |
| `unplaced` | tens, not hundreds |
| `shipped rows` | 2,500 and rising as the rules improve |
| names shared by more than one stop | hundreds is normal (JDF writes the same stop with and without a part); "of which shipped none" should be 0 or 1 |

Red flags, in the order they have actually bitten:

- **A position far from its village.** Check the OSM query is scoped to the right area and
  that the bare-name radius is applied. A bounding box pulled in neighbouring regions and
  produced positions 90 km out.
- **Long hops between adjacent stops.** Means the isolation guard is not running, or the
  archive cache lost the distances (`runs with distances:` should not be 0).
- **Mass rejections after touching a guard.** If a guard rejects a third of the table it is
  probably reading the distance column on looping runs; `runs skipped as looping` should be
  in the hundreds, not zero.
- **A rule that places stops further from the line than the accuracy it claims.** Check the
  radius constants in stage 6 against the accuracy in the row: 200 m claimed from a 4 km
  radius is a lie in the app's own vocabulary.
- **Coverage dropping after an "improvement".** Matching is greedy: a new tier tried too
  early steals stops from a better one. Order the tiers by specificity, and run stages 3 to
  7 to see the whole effect.
- **The app failing to read the file.** Every kind the pipeline can write has to exist in
  `StopPosition.Match`; a missing case makes the whole bundle undecodable and the map
  silently shows no stops at all. `VdvLiveTests/StopPositionsTests.swift` reads the shipped
  file and fails loudly when this happens, which is the only reason to trust a green run.

## Do not

- Do not try to mine stop positions from the feed at scale: the last stop name only exists in
  `OpenInfoWindow` (one request per vehicle), so covering the region would mean thousands of
  requests against a site the app depends on.
- Do not publish a position whose only evidence is a name match with no distinguishing part.
- Do not invent a position to fill a gap in the review: leave it there instead. A stop with no
  position is a smaller lie than a stop in the wrong village.
- Do not add OpenStreetMap-derived data without attribution: the table is ODbL, and the
  credits screen has to say so.

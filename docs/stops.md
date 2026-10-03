# Stops: where they are, and what it costs to find out

Investigation and implementation record, checked against the live sources on 2026-10-03.
The commands to reproduce each claim are at the end.

## Short version

- **The timetables ship stop names but no positions.** JDF's `Zastavky.txt` has no
  coordinate columns at all - its columns 7-12 are tariff zones - and the ministry's NeTEx
  export of the same data has an *empty* `<Location />` for all 327,110 of its scheduled
  stop points. There is nothing to switch on.
- **The region publishes nothing.** Kraj Vysočina's own open-data catalogue holds three
  datasets and none of them is transport, and the region is not among the providers of the
  27 "zastávky" datasets on data.gov.cz. Other regions do publish stop layers (Karlovarský,
  Královéhradecký, Ústecký from JDF via CIS, PID, and IDS JMK built from GTFS), so the
  dataset type is normal - Vysočina just does not have one.
- **The live feed cannot be mined politely.** It reports a vehicle's position and its line,
  but the stop it last called at only exists in `OpenInfoWindow` - one request per vehicle.
  Covering the region that way would mean thousands of requests against the site the app
  depends on.
- **So positions are matched, not looked up.** OpenStreetMap is the only source with
  positions for this region, and the only handle on a stop is its name. Of the region's
  **3,521 stops, 2,184 (62%)** get a position from an actual OpenStreetMap stop; **1,762**
  survive de-duplication of display names and are shipped.
- **1,067 stops (30%) have only a village centre** and **270 (8%) have nothing**. The
  village centres are deliberately *not* shipped: they are within a few hundred metres of
  everything in that village, which for a dot with a stop name on a map is a guess, not a
  position.

## What each source actually has

| Source | Stop names | Stop positions | Notes |
|---|---|---|---|
| JDF archive (`Zastavky.txt`) | yes | **no** | 309,789 stop rows; columns 7-12 hold only 2-digit tariff zones; 0 coordinate-shaped cells |
| NeTEx export (same ministry, 190 MB) | yes | **no** | 309,789 `StopPlace`, 327,110 `ScheduledStopPoint`, 0 `Latitude`, every `<Location />` empty |
| Live feed (`mapavdv`) | current stop only | vehicles only | 6 Ajax endpoints in the whole site, none stop-based; no coordinates in the info-window or timetable HTML |
| Kraj Vysočina | — | — | ArcGIS Hub catalogue: 3 datasets, 0 transport |
| ČÚZK ZABAGED | rail | rail | 149 layers; "Železniční stanice, zastávka" exists, no bus-stop layer |
| **OpenStreetMap** | yes | **yes** | 6,437 named stops with positions in the region, 3,616 distinct names |

The JDF stop ids are per line (`Zaslinky.txt` refers to `Zastavky.txt` by a number that
restarts on every line), so no external dataset can be joined by id either. **The name is
the only key**, which is what makes matching the whole problem.

## How the join works

Stops are kept when their JDF district is one of JI, TR, PE, HB, ZR: 3,521 stops across
1,033 lines, 2,590 distinct display names. Each one is matched in this order, and the result
carries which rule matched and how close it is likely to be:

| Match | Rule | Accuracy |
|---|---|---|
| `osm-name` | the name in the forms a timetable prints it in | ~40 m |
| `osm-village` | OSM name starts with the village and carries our local name | ~150 m |
| `osm-near` | a hamlet stop, filed in OSM under the hamlet alone, within 5 km of the village | ~250 m |
| `place` | the village centre - **not shipped** | ~600 m |

Three things keep this honest, and each of them was added because the join got it wrong:

1. **Candidates come from inside the region, not a bounding box.** With a bounding box the
   neighbouring regions answered for our villages: "Kramolín", "Suchá", "Borovnice" and
   "Březí" are common enough to exist twice, and the first run placed them 85-91 km away.
2. **A bare village name is only believed within 15 km of that village.** "Petrovice" has no
   distinguishing part left once the district suffix is stripped, and matched a Petrovice
   40 km from the line it belongs to.
3. **Two guards judge the result.** A position more than 12 km from every other stop its line
   calls at is wrong - a bus does not serve one stop twenty kilometres from the rest of its
   route - and, where a run's own distances are usable, two neighbouring calls cannot
   straight-line further than 1.6x their timetable distance plus 3 km.

The second guard needs a caveat that cost some coverage to learn: **the distance column
counts down to the end of the run**, so on a route that loops back it is not monotone and the
difference between two calls says nothing about how far apart they are. Those runs are
skipped (440 of 1,017) rather than used to reject correct positions.

## What is shipped, and what it costs

`VdvLive/Resources/stop-positions.json`, 225 KB, keys washed down to letters and digits
(`Okříšky,aut.nádr.` → `okriskyautnadr`), values carrying the display name, the position, the
match kind and the accuracy in metres. `StopPositions` in the app folds a stop name the same
way and looks it up; `StopPosition.isExact` is false only for the village centres, which are
not in the file by default.

Red flags the generator prints, and what they should read:

| Reading | Healthy |
|---|---|
| `osm-name` | ~52% |
| `osm-name` + `osm-village` + `osm-near` | ~62% of the region's stops |
| `positions rejected` | low hundreds, not thousands |
| published entries | ~1,800 |

## Drawing them

The table reaches the map behind a preference: **Settings ▸ Preferences ▸ Stops ▸ "Show stops on the map"**, off by default. Off, because the positions cover most of the region and not all of it, and a map that quietly drew two thirds of the stops would read as a map that had gone wrong rather than as one that was honest.

`VehicleMapViewModel.stopFlags` is what the layer asks for. It answers from three things: the preference, the viewport, and how far the map is zoomed in (`stopFlagsSpanMetres`, 15 km across). At region zoom the whole region is on screen with over a thousand known stops, which would cover the map instead of telling the reader anything, so the flags appear once the map is close enough for a flag to mean something - in practice from a few hundred metres to a couple of kilometres on the scale bar. Nothing reads the shipped table until the option is turned on.

The marker is a flag (`StopAnnotationView`) rather than a dot: a stop is a fixed point the reader looks up, not something that moves, and the vehicles already own the dot-and-badge vocabulary. Flags are drawn under the vehicles, so a bus is never hidden by a stop it is about to call at.

## Known weaknesses

- **Some matches are still out.** Judged by distance to a village centre of the same name,
  about 4% of published rows look suspicious; that metric is itself unreliable where a
  village name exists twice, so the honest statement is that a small minority is suspect and
  the two guards are what remove the gross errors.
- **District-scoped candidates do not work yet.** Asking Overpass for an okres with an area
  selector returns nothing (and 504s) often enough that the script falls back to the region
  bounding box. The district buckets are in the file format and the script, so this improves
  by itself when Overpass answers.
- **The remaining 1,067 stops are in villages where OSM has no stop** (about 500 of them are
  places where OSM does have *some* stop, but named by hamlet or by roman numeral, which
  name matching cannot resolve).

## Options not taken

- **Mining the feed.** Positions could be inferred with an exact join: the feed names the
  stop a vehicle last called at, so the position at the moment that name changes is that
  stop's position. It needs ~10-20 s sampling of each vehicle, i.e. one request per vehicle
  per sample, which is not something to do to a site the app relies on - a polite collector
  would have to rotate through a handful of vehicles over days. Worth revisiting if the
  remaining stops matter, and the app itself could contribute samples from the cards the user
  opens, which cost no extra requests.
- **Interpolating between anchored stops** using the timetable distances and the road
  network. Straight-line interpolation was rejected: for a stop 1 km off, the dot is in a
  field rather than on the road.
- **ZABAGED and the regional layers**, for the reasons in the table above.

## Licence

The JDF archive is CC BY 4.0 with a sui generis database right (attribution required, and
wholesale re-publication is not on). **OpenStreetMap data is ODbL 1.0**: the app has to
credit it, which the acknowledgements screen already does for the map and timetable data,
and a stop table derived from it carries share-alike obligations.

## Reproducing

```sh
make stops                      # downloads the JDF archive if needed, then regenerates the table
python3 tools/stop_positions.py /tmp/jdf/JDF.zip VdvLive/Resources/stop-positions.json

# The claims about the sources
unzip -l /tmp/jdf/JDF.zip | wc -l                       # 13,180 entries
python3 -c "import zipfile;z=zipfile.ZipFile('/tmp/jdf/JDF.zip');print(len(z.namelist()))"
curl -s https://portal.cisjr.cz/pub/seznamy/zastavky.csv | head -3      # names only
curl -sI https://portal.cisjr.cz/pub/netex/NeTEx_VerejnaLinkovaDoprava.zip   # 199,098,929 bytes
curl -s "https://data.kr-vysocina.cz/api/feed/dcat-us/1.1.json" | head -c 200
```

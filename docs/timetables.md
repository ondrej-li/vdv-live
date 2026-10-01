# Timetables: what is available, and what the app could do with it

Investigation, not a design for code. Everything below was checked against the
live sources on 2026-09-30; the commands to reproduce each claim are at the end.

## Short version

- The official timetable data is **JDF**, one 106 MB zip of **13,259 per-line
  zips**, published by the Ministry of Transport three times a week. There is
  **no GTFS for Vysočina** and **no regional subset** of any kind.
- **The join to the live feed works**, and it is exact: the feed's `text`
  (`764337`) is a JDF line number, and the info window's `Spoj` is a JDF run
  number. Verified against six live vehicles.
- Entry names inside the archive are opaque ids, so a line cannot be requested by
  number — **but the archive is a plain zip over HTTP with working range
  requests**, and the mapping can be derived by scanning it in about a second.
  A line's whole timetable is then a **2–30 KB** range fetch.
- The region itself publishes nothing transport related, and the map's own API has
  **no geometry and no stop departures**.
- Recommendation: use the official data **per line, on demand** (Strategy A) for
  the lines the user actually looks at, and offer the full regional extract as an
  opt-in download (Strategy B) later. Do the physical plausibility filter for the
  "impossible jumps" separately — no timetable source will fix that.

## The official data

| | |
|---|---|
| Dataset | *Jízdní řády veřejné linkové dopravy* |
| Publisher | Ministerstvo dopravy (MD), IČO 66003008 |
| Page | `data.gov.cz/zdroj/datové-sady/66003008/1463646434` |
| Download | `https://portal.cisjr.cz/pub/JDF/JDF.zip` — **106,842,823 bytes** |
| Format | JDF 1.11 (CIS JŘ fixed format), text, **CP1250** |
| Contents | 13,259 entries, each a small zip with one line's timetable |
| Cadence | **three times a week** (`last-modified` was 28 Sep 2026 19:00) |
| Licence | CC BY 4.0 per the portal; the distribution carries the **sui generis**
| | database right ("zvláštní právo pořizovatele databáze: obsahuje"), so |
| | attribution is required and wholesale re-publication is not on. |
| Server | supports ranges: `206`, `accept-ranges: bytes`, `ETag`, `Last-Modified` |

The server also answers a `HEAD`, and both it and a **one byte range** carry those
three identifiers, which is what the app's "check for updates" is built on: asking
whether a downloaded index is still the published one costs about a kilobyte
rather than a re-download. Measured again on 2026-10-01 the archive was
**106,230,086 bytes** with `last-modified: Wed, 30 Sep 2026 19:49:29 GMT` and
`etag: "a3306dce1451dd1:0"` — the size had gone **down** since the 2026-09-30
figures above, so the date and the ETag identify a publication, not the size.

Also published, all worse for a phone:

- `pub/netex/NeTEx_VerejnaLinkovaDoprava.zip` — **200 MB**, XML, same content.
- `pub/netex/NeTEx_DrahyMestske.zip` — 50 MB, trams/trolleybuses.
- `pub/seznamy/*.csv` — small lists, **but only names and numbers, no ids**, so
  they are of no use for joining (`linky.csv` has 5,169 line numbers, which is
  not the 13,259 archive entries).

## What is inside one line's zip

Line `764337` (the app's pinned line 337) is entry `853.zip`:

| File | What it gives |
|---|---|
| `Linky.txt` | line number (`764337`), route name ("Třešť-Brtnice-Okříšky-Radonín"), operator id, validity dates |
| `Spoje.txt` | the runs of the line (`spoj` numbers) |
| `Zaslinky.txt` | the line's stops in order, with stop ids |
| `Zastavky.txt` | stop id → municipality, part, district |
| `Zasspoje.txt` | **the timetable itself**: run × stop → arrival and departure (`HHMM`) |
| `Caskody.txt` | per-run day-type codes and validity dates |
| `Dopravci.txt`, `LinExt.txt`, `Navaznosti.txt`, `Pevnykod.txt`, `Udaje.txt`, `VerzeJDF.txt` | operator, line extension, connections, codes, notes, version |

`LinExt.txt` of that line carries the short number `631` next to `725631`, which
is the operator-prefix rule the app already relies on (`764337` = operator 764 /
line 337) — confirmed from the source rather than inferred.

## Does it join to the live feed?

Yes. Three things had to be true, and all three were checked against live data:

1. **Line.** The feed's `text` is a JDF line number. `764337` is entry `853.zip`,
   route "Třešť-Brtnice-Okříšky-Radonín", operator `26060451`. The app's test
   fixture `764931` is entry `9168.zip`, "Telč-Mrákotín-Studená-Strimilov".
2. **Run.** Six live vehicles taken from `GetPoints`, each asked for its info
   window, then looked up in JDF by line and `Spoj`: every pair was found, e.g.
   `841122` + spoj `25` exists in seven entries, `841104` + `25`, `841460` + `29`.
   So `Spoj` needs no translation.
3. **Stops.** JDF stores municipality and part separately (`Heršpice`, `zelnice`),
   which composes to the feed's `Zastávka` style ("Telč,Hradecká škola"). Two
   quirks: stops carry tariff suffixes (`Vír [ZR]`) and some lines are listed
   with an empty part.

Not verified: **which dates each day-type code runs on.** Each line's zip has the
codes per run, but the calendar that turns a code into dates may live outside the
per-line package. Until that is settled, "does this run operate today" cannot be
answered from the line zip alone.

One line can map to **several entries** (381 Vysočina lines come from 1,051
entries). They differ by operator and by tariff variant, so when picking one the
app has to match the stop sequence or direction, not just the line number.

## What the region and the map already offer

- **Kraj Vysočina publishes no transport data**: querying the national catalogue
  for that publisher returns land-use and budget datasets only. Other regions
  (Prague, Hradec Králové, Olomouc, Liberec, Moravia-Silesia, South Bohemia,
  Karlovy Vary) publish stop geodata; Vysočina does not. That is worth raising
  with the region — stop coordinates would help the app a lot.
- **The map's own API has seven endpoints**: `GetPoints`, `OpenInfoWindow`,
  `GetTimetable`, `GetVehiclesByLine`, `GetSelectVehiclesPartialView`,
  `GetColorsConfig`. No route geometry, no stop-level departures, no stop list.

## What the app could do with it

| # | Feature | Needs | Value | Effort |
|---|---|---|---|---|
| 1 | Reliable "last stop"/"next stop" for **every** vehicle | line + run + stop times | Fixes the line 420 hole, which the map's own endpoint cannot fill | Low |
| 2 | Planned times and **how late** a vehicle actually is | above + scheduled times | The card finally says something about the future | Low |
| 3 | Stops of a line, in order | `Zaslinky` + `Zastavky` | Position in the run, "3 stops to go" | Low |
| 4 | Which runs exist today, and the next ones | day-type calendar | Pinned lines that are not running can still show "next departure 14:32" | Medium |
| 5 | Departures from a stop | all lines' zips (Strategy B) | A genuinely useful second screen | Medium |
| 6 | Search for a stop or a line | regional extract (B) | Discoverability, and pins by stop instead of by number | Medium |
| 7 | Works with the feed down | regional extract (B) | Schedules are local, real-time is best effort | Medium |
| 8 | Plausibility filter for jumps | **nothing from JDF** | Kills the "bus jumps several km" artefact | Low, separate |

Note the gap: JDF has **no coordinates and no route shapes**, so it cannot snap a
vehicle to its route. Feature 8 therefore has to be physical (a vehicle that
would have to travel faster than, say, 90 km/h between two payloads is a data
glitch — clamp it, or hold the previous position instead of gliding). That is
worth doing on its own, and it is the only honest fix for the jumps until a
geometry source appears.

## Getting the data onto the phone

**Strategy A — per line, on demand (recommended first).**

1. Ship a mapping of line number → archive entry, produced offline by scanning
   the archive (the scan that produced the numbers above took **1.4 seconds** for
   the whole country in Python; on device it is not needed at all in this
   strategy). A table of 13,259 rows is a few hundred KB of text, far less if
   only the 381 Vysočina lines are kept.
2. When a line is needed (vehicle selected, line pinned), fetch **that entry only**
   with two range requests — the central directory, then the entry — and check
   `Linky.txt` really names the requested line. Cache it, keyed by line and by
   the archive's `ETag`.
3. Line 337's whole timetable is about 25 KB compressed; the buses the user
   actually looks at are a handful of lines, so the phone never sees the 106 MB.

Risk: if entry names are reassigned on republication, the shipped mapping goes
stale. The `Linky.txt` check turns that into a graceful failure (fall back to the
map's own endpoint, offer Strategy B) rather than a wrong timetable.

**Strategy B — one regional extract, opt-in.**

Download the 106 MB once, inflate the entries, keep only Vysočina: **1,051
entries = 381 lines = 527,930 stop calls = 37 MB of text**, maybe 10–20 MB in a
compact store. Then departures per stop, calendar questions and offline use all
become local. On device this needs a zip reader (no dependency exists in the app
today; `Compression` plus a small container parser is the way) and a one-off
scan, so it belongs behind an explicit "download timetables (Wi-Fi only)" action
with progress, not in the launch path.

**Hybrid, if both are done:** A for the lines in use, B as an upgrade for the
people who want stop-level search.

## Risks

| Risk | Mitigation |
|---|---|
| Mapping stale after a republication | Verify `Linky.txt` per fetch; fall back and re-derive |
| 106 MB download on mobile data | Strategy A needs no big download; B is opt-in and Wi-Fi only |
| Attribution obligations | Credits screen naming MD ČR / CIS JŘ and the licence, in both languages |
| CP1250 text | `String.Encoding.windowsCP1250` is available on iOS |
| Zip reading with no dependencies | `Compression` framework for inflate, hand-written central directory reader |
| Several entries per line | Pick by stop sequence, merge if needed |
| Timetable validity dates | `Linky.txt` and `Caskody.txt` carry them; respect them |

## Suggested phases

**What has been built (2026-09-30):** steps 1 and 2, plus the settings screen that
gates them. See "What was built" below for how the delivery differs from the plan.

1. **Prove the fetch path.** Range-fetch one entry for a pinned line, inflate it,
   parse `Linky`, `Spoje`, `Zaslinky`, `Zastavky`, `Zasspoje`. Verify against the
   app's existing timetable for the same run. No UI change.
2. **Use it in the detail card.** Fill the last/next stop and their planned times
   from JDF, keeping the map endpoint as the fallback. This is where the line 420
   complaint actually gets fixed, and where a delay becomes expressible.
3. **Show stops of the line.** "4 stops to go" from `Zaslinky` plus the reported
   stop, which also gives a sanity check on the position.
4. **Plausibility filter** for implausible movement (independent of everything
   above).
5. **Later:** the calendar, departures per stop, and the regional extract behind a
   settings action.

## Open questions

- Are archive entry names stable across the three-times-weekly republication?
  Two exports compared would answer it; only one is available today.
- Which dates does each day-type code cover, and does it need a file outside the
  per-line zip?
- Meaning of the two unexplained numeric columns in `Zasspoje.txt`.
- Does the NeTEx export carry route geometry (`RouteLink`) that JDF lacks? If it
  does, it is worth a separate look despite the size — it is the only route to
  snapping a vehicle onto its road.
- The region has no stop geodata. Stop coordinates from an official source would
  improve both the map and the plausibility filter.

## What was built

Implemented on 2026-09-30:

| Piece | Where |
|---|---|
| Zip reader (central directory, entries, raw deflate) | `VdvLive/Data/ZipArchive.swift` |
| JDF reader for one line | `VdvLive/Data/JDFTimetableParser.swift` |
| Timetable model, including request stops | `VdvLive/Domain/LineTimetable.swift` |
| Archive client (range requests) | `VdvLive/Data/TimetableArchiveClient.swift` |
| Index, per-line fetch, disk cache, verification | `VdvLive/Data/LineTimetableStore.swift` |
| Line to entry mapping (381 lines, 22 KB) | `VdvLive/Resources/jdf-lines.json`, generated by `tools/jdf_lines_mapping.py` |
| Settings download, stops list with delays | `SettingsSheet`, `VehicleStopsView` |

Two decisions differ from the plan, both in the app's favour:

- **The line to entry mapping ships with the app.** Deriving it on the phone would
  mean reading all 13,259 entries, which means the whole 106 MB. Baking in the
  names (22 KB for the region) removes that download entirely. Every fetch still
  checks the line number in the entry's own `Linky.txt` and refuses a mismatch, so
  a stale mapping costs a missing timetable rather than a wrong one. Refreshing a
  stale mapping is the open problem below.
- **The settings download is the central directory, about two megabytes**, not the
  archive. The directory says where every entry lives; a line is then a few
  kilobytes. The 106 MB regional extract stays available as the later, heavier
  option for stop-level search and offline departures.

Still open: the day-type calendar, departures per stop, and the "how long until it
reaches my stop" question, which needs the calendar plus a chosen stop.

## How these claims were checked

The scripts are in `tools/`. The JDF ones read `JDF.zip` from the working
directory, so download it there first:

```sh
mkdir -p /tmp/jdf && cd /tmp/jdf
curl -O https://portal.cisjr.cz/pub/JDF/JDF.zip          # 106 MB
/opt/homebrew/bin/python3 /path/to/vdvmap/tools/jdf_scan.py
```

```sh
# 13,259 entries, and line 764337 is entry 853.zip
python3 tools/jdf_scan.py

# how much of it the region needs
python3 tools/jdf_region_size.py
#   entries: 13259, touching Vysočina: 1051, lines: 381, calls: 527930, text: 37.1 MB

# the join, against live vehicles
python3 tools/jdf_joincheck.py

# what the map's own API offers, and what the region publishes
python3 tools/cisjr_endpoints.py
```

Also checked by hand, outside those scripts:

```sh
# what is published and how big
curl -sI https://portal.cisjr.cz/pub/JDF/JDF.zip
curl -s  https://portal.cisjr.cz/pub/            # JDF, netex, seznamy, draha

# ranges work - the whole Strategy A depends on this
curl -s -D - -o /dev/null -r 0-99 https://portal.cisjr.cz/pub/JDF/JDF.zip
```

Checked on macOS with `/opt/homebrew/bin/python3`; the scripts only use the
standard library.

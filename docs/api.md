# The vehicle feed

The app has exactly one data source: the AJAX endpoint that powers the public
map at <https://mapavdv.kr-vysocina.cz/>.

```
GET https://mapavdv.kr-vysocina.cz/Ajax/GetPoints
```

It answers with a JSON array, one element per vehicle currently being tracked:

```json
[
  {
    "id": 172923,
    "lat": 49.39595413208008,
    "lng": 16.366287231445312,
    "text": "841334",
    "delay": 5,
    "finalStopName": "Byst\u0159ice n.Pern.,aut.n\u00E1dr.",
    "traction": "BUS"
  }
]
```

The request the app sends is deliberately close to what the site's own front end
sends:

```sh
curl 'https://mapavdv.kr-vysocina.cz/Ajax/GetPoints' \
  -H 'Accept: */*' \
  -H 'Accept-Language: en-US,en;q=0.7' \
  -H 'Referer: https://mapavdv.kr-vysocina.cz/' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ...'
```

`Sec-Fetch-*`, `sec-ch-ua*`, `Connection` and `Sec-GPC` from a browser request
are not sent: `URLSession` manages connection headers itself, and the endpoint
does not require the client hint headers. The `sznlbr` session cookie the site
sets is optional and configurable through
`VehicleRequestConfiguration.sessionCookie` in case the endpoint ever starts
requiring it.

## Fields

| Field | Type | Notes |
|---|---|---|
| `id` | integer | Unique within one response. Trains and vehicles outside the public timetable use **negative** ids (for example `-2435`). |
| `lat`, `lng` | number | WGS 84 degrees. Also sent as integers when they are whole numbers. |
| `text` | string | Line code. For buses this is usually six digits: **three for the licence area and three for the line**, so `764337` is line `337` registered in licence area `764`. Train numbers (four to seven digits) and the short codes on some regional lines carry no prefix. |
| `delay` | integer | Minutes. See the caveats below. |
| `finalStopName` | string | Final stop, never empty. Placeholders such as `-1 N/a` or `5437035 N/a` mean "not known". |
| `traction` | string | `BUS`, `TRAIN` and `UNKNOWN` were observed. The app keeps `TROLLEYBUS`, `TRAM` and `FERRY` ready and maps anything else onto `UNKNOWN`. |

### Line codes and licence areas

The licence area prefix is what makes the feed's `text` look odd next to a printed
timetable. In one capture, 520 of 605 records were six-digit codes, and their
prefixes group the way the licence registers group: `358`, `603`, `764`,
`841`, `842`, `795`, `796`, `680`, `340`, `761`, `200`. `LineCode` splits them,
the app shows the line number a passenger would recognise (`337`, `815`) and
keeps the licence area (`764`, `795`) as a label on the detail card.

Pinned lines are stored as line numbers, so pinning `337` catches `764337` and
`841337` alike, while pinning `764337` is filed as `337`.

## The two endpoints behind the detail card

`/Ajax/GetPoints` has no notion of where a vehicle is in its run. The map's own
marker popup is served by two further endpoints, both of which answer with
**HTML**, not JSON.

```
GET /Ajax/OpenInfoWindow?id=<vehicle id>
GET /Ajax/GetTimetable?vehicleNumber=<vehicle id>&currentStopId=<stop id or 0>
```

`OpenInfoWindow` returns a two-column table:

```html
<tr><th>Linka</th><td>764931</td></tr>
<tr><th>Spoj</th><td>11</td></tr>
<tr><th>Bezbarierov&#xFD;</th><td><input type="checkbox" disabled></td></tr>
<tr><th>Zast&#xE1;vka</th><td>Tel&#x10D;,Hradeck&#xE1; &#x161;kola</td></tr>
<tr><th>Zpo&#x17E;d&#x11B;n&#xED;</th><td>0 min.</td></tr>
```

which is `Linka` (line), `Spoj` (which run of the line, e.g. the 11th service of
the day), `Bezbarierový` (a disabled checkbox, ticked for accessible vehicles),
`Zastávka` (where the vehicle last was, see below) and `Zpoždění` (delay).

`GetTimetable` returns the stop list of that run, with an arrival and a
departure column, which is what makes it possible to name the **next** stop. Its
heading repeats which run it describes:

```html
<span>Linkospoj:</span>
<span>764931 / 11</span>
<span>-- / --</span>
```

The second line is filled in when the endpoint knows the vehicle; `-- / --` is
what it answers for a vehicle it cannot place (see below).

Notes for anyone touching the parsing:

- Every non-ASCII character is escaped numerically and in hexadecimal
  (`&#x10D;` is `č`), so ``HTMLEntities`` decodes them.
- The accessibility label is spelled `Bezbarierový`, without the háček, while the
  stop label carries full diacritics. Labels are therefore matched with
  diacritics folded away rather than character by character.
- `vehicleNumber` in `GetTimetable` is a vehicle **id**, not a line, and the
  site's own front end always sends `currentStopId=0`.
- **The timetable endpoint does not always answer for the vehicle it was asked
  about.** It resolves the run itself from the vehicle id, and when it cannot it
  either answers `Jízdní řád se nepodařilo načíst.` ("the timetable could not be
  loaded") with no stops at all, or - worse - a run that belongs to something
  else. Observed on the two live vehicles of line `420` (`-114` and `-203`, both
  reporting traction `UNKNOWN`): both have a `Zastávka` but no usable timetable.
  The app therefore compares the `Linkospoj` line and `Spoj` in the answer with
  the values in the info window and drops the stop list unless they agree, and
  shows `Timetable for this service is not available.` when there is none. A
  wrong next stop is worse than no next stop.
- The timetable is only a bonus: without it the card still has the line, the
  service number and the last reported stop.

### What "Zastávka" means

`Zastávka` is where the vehicle was **last seen** - its last known position on
the run - not the stop it is heading to. The card labels it `Last stop` for that
reason, and takes the scheduled time for it from the run's timetable when the
cross-check above confirms the run. The following entry of that run is the
`Next stop`.

## Quirks the app has to absorb

Verified against a live capture of 448 records:

- **`delay` uses `-2147483648` (`Int32.min`) as "no information"** - roughly a
  third of all records. `VehicleDelay` maps that onto `.unknown`; everything
  else, including negatives, is a real value. Values between `-301` and `425`
  appear in the wild, so the app does not clamp them.
- **Vehicles without a position** are published with `lat: 0, lng: 0` (one
  record in the capture). They would land in the Gulf of Guinea, so
  `Vehicle.isLocatable` filters them out; the decoder reports how many it
  dropped.
- **Placeholder destinations**: `X N/a` or `-1 N/a` instead of a stop name.
  `VehicleDTO.normalizedDestination` turns those into `nil`.
- **A few records sit far outside the region** - Prague, Brno, České
  Budějovice, and occasionally Italy or France while a bus runs a long distance
  service. They are kept and simply fall outside the map's camera bounds.
- **The array is not guaranteed to be homogeneous.** If a single record stops
  matching the shape of its neighbours, the whole response would otherwise be
  lost. `VehiclePayloadDecoder` therefore retries record by record and reports
  `skippedRecordCount`; the map keeps whatever could be read.

## Open question: what `delay` means for some vehicles

For buses with a normal `text` (a line number) and a real `finalStopName`,
`delay` behaves like minutes behind schedule: small values around `0`, both
signs, consistent with the site's own delay colouring.

Records with `"traction": "UNKNOWN"` behave differently. They carry bus-like
stop ids (`text: "357301"`), a placeholder destination and large, round
`delay` values (`337`, `357`, `425`). That looks more like a countdown to the
next departure than a schedule deviation, and there is no documented API to
confirm it.

Until that is settled the app shows the number as reported, prefixed with `+`,
and colours it as a delay. If it turns out to be a different quantity, only
`VehicleDelay+Presentation.swift` and the detail row need to change.

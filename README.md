# VDV Map

An iOS app that shows the live positions of buses and trains in the Vysočina
Region (Czechia) on Apple Maps.

The data comes from the public map at
`https://mapavdv.kr-vysocina.cz/`, which publishes every tracked vehicle as a
JSON array. The app polls that endpoint, groups nearby vehicles into markers and
draws them on a map that is framed - and locked - to the region.

<p align="center">
  <img src="VdvMap/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="180" alt="App icon: a white bus on a blue to teal gradient">
</p>

## What it does today

- **Live map of the region.** Apple Maps, standard style, camera restricted to
  the Vysočina Region so the map cannot be panned into the sea.
- **Distance legend.** A small scale bar under the header says what a stretch of
  the map is worth ("10 km"), so a marker a couple of centimetres away can be
  read as a real distance. It follows the zoom level and rounds to numbers worth
  labelling. It is worked out from the latitude span MapKit fits to the map's
  height, which is exact while the camera is flat - tilting the map stretches
  the projection, and then it is only roughly right.
- **Refresh countdown.** A hairline, translucent rainbow grows along the top edge
  of the header card over one refresh interval, so it answers "when is this
  updated next?" without asking for attention: it is faint enough to go
  unnoticed until you look for it. It sits inside the straight part of that edge,
  clear of the rounded corners, and it is not drawn at all when automatic refresh
  is off, because then there is no next refresh to count down to.
- **Vehicles move instead of jumping.** Each payload puts a bus somewhere new, so
  the markers travel there over two seconds - a straight line at a constant speed
  from the position they were drawn at to the position the feed reports. Markers
  that appear or disappear are placed immediately: only the ones already on
  screen travel, and zooming re-cuts the grid, which lands every marker at once.
  The movement is sampled 30 times a second, so judge it in DeviceHub: the
  browser mirror in `make live` shows about one frame per second by construction.
- **A vehicle that goes quiet is held on to.** The feed drops a vehicle for a
  payload or two before reporting it again, so a marker that stops being reported
  stays where it was last seen, drawn grey, and leaves the map only after five
  consecutive payloads without news. A greyed marker carrying a live bus is never
  drawn grey: a cluster is stale only when nothing in it is being reported. A
  failed load is not news either, so it never ages anything, and the header count
  keeps counting what the feed actually reports.
- **Markers grouped by zoom level.** The visible region is split into a grid, so
  a few hundred vehicles collapse into at most a hundred markers while zoomed
  out and split apart as you zoom in. A marker shows a line number for a single
  vehicle and a count for several.
- **Detail card.** Tap a marker for the line, destination, traction and delay.
  The line is shown the way a passenger knows it - `815` rather than `795815`,
  with `795` named as the operator - and for a single vehicle the app also looks
  up the run: the service number (`Spoj`), the last reported stop (`Zastávka`,
  the last known position of the vehicle), the next stop with their timetable
  times, and whether the vehicle is accessible. Tap one vehicle of a merged
  marker to fly to it. The timetable endpoint is cross-checked against the run
  the info window names, so a page for a different run is ignored rather than
  producing a wrong next stop; when the timetable is unavailable the card says so.
- **Pinned lines.** Pin the lines you care about, either from a vehicle's star on
  the map or by number in the pinned lines screen. A pinned line stays in the list
  when it is not running, which matters for a line that only operates at certain
  hours. Pin 420 and 337 and the map rings their markers in amber with a star, and
  the `Pinned` chip filters the map down to them.
- **A quiet map that stays quiet.** Choosing the `Pinned` filter is remembered
  across launches (there is a switch for it in the pinned lines screen too), so
  showing only your own lines is one decision rather than one per launch. If none
  of them happen to be in view the banner says so and offers a jump to the first
  pinned line that is running.
- **Traction filter.** Chips for the tractions actually present in the last
  payload.
- **Refresh.** Manual refresh, plus automatic refresh that can be paused. The
  interval is chosen in the settings and remembered: anything from 5 seconds up,
  15 by default.
- **Settings.** One screen for the refresh interval (automatic refresh can also
  be turned off there) and the language. Czech is the default; English and
  "follow the device" are one tap away. A language change is written to
  `AppleLanguages` and shows up the next time the app is launched, which is what
  the screen says.
- **Official timetables, on demand.** The settings screen downloads the index of
the Ministry of Transport's timetable archive (a couple of megabytes, once).
After that, the card of a selected bus lists **all the stops of its run** with the
times they are actually expected - the published time moved by the delay the feed
reports - and marks the stop the vehicle was last seen at. Request stops, which
the archive marks with `<`, are labelled as such instead of being given a time.
Each line's timetable is then fetched on its own, a few kilobytes at a time, and
kept on disk, so it works offline afterwards. `docs/timetables.md` has the whole
investigation, including why the 106 MB archive is never downloaded.
- **Honest failure handling.** Errors keep the last good data on screen and show
  a banner with a retry button.

## Getting started

Requirements: Xcode 26 or newer and iOS 18 or newer on the device or simulator.
There are no third party dependencies, so there is nothing to resolve before
building.

```sh
open VdvMap.xcodeproj          # or: make open
make build                     # build for the simulator
make test                      # run the unit tests
make run                       # build, install and launch on a simulator
make screenshot                # save one frame of the running app
make live                      # mirror the running app into a browser tab, 1 fps
make devices                   # list simulators, then: make run SIMULATOR="iPhone 16"
```

`make run` installs and launches the app whether or not a Simulator window is
available. Some Xcode installations (including trimmed ones that lack
`Contents/Developer/Applications/Simulator.app`) can only run devices headlessly,
so the app is there but there is no window to look at; open the device in Xcode's
DeviceHub, or use `make screenshot` / `make live`. `make live` is a read-only
mirror, so interactions have to go through DeviceHub, Xcode or a device build.

The Xcode project uses file system synchronised groups, so new files inside
`VdvMap/` or `VdvMapTests/` are picked up automatically - there is no `.pbxproj`
merge conflict to worry about.

If the command line tools are pointed at the Command Line Tools rather than
Xcode, `make` already passes `DEVELOPER_DIR` for you. If `xcodebuild` still
refuses to run with a licence message, accept it once:

```sh
sudo xcodebuild -license accept
```

## Project layout

```
VdvMap/
  App/            entry point and the one place that builds the live stack
  Domain/         value types: Vehicle, Traction, VehicleDelay, FavouriteLines,
                  the region, the grid clusterer that turns vehicles into markers,
                  and the app settings and language
  Data/           the feed client, its request configuration, the decoder, and the
                  pinned-lines and settings stores
  Features/       the map screen, its view model, the pinned lines screen and the
                  settings screen
  DesignSystem/   colours and symbols for domain values
  Resources/      asset catalog (app icon, accent colour)
  Support/        sample data used by SwiftUI previews (#if DEBUG)
  Localizable.xcstrings   English source strings with Czech translations
VdvMapTests/      unit tests plus JSON fixtures captured from the live feed
tools/            the app icon generator, the live mirror page, and the JDF
                  investigation scripts (see docs/timetables.md)
docs/api.md       what the feed returns, as verified against a live sample
docs/timetables.md  what official timetable data exists, how it joins to the
                  live feed, and what the app could do with it
```

The dependency direction is one way: `Features` knows `Domain` and `Data`,
`Data` knows `Domain`, and `Domain` knows nobody. Networking sits behind the
`VehicleFetching` protocol, which is what makes the view model testable without
a network.

## Testing

`make test` runs the unit tests, which cover:

- decoding the feed, including every quirk listed in `docs/api.md`
- the delay sentinel and the `N/a` destination placeholder
- line codes: operator prefixes, matching a pinned line against `764337`, and
  grouping the running lines by the passenger facing number
- the detail card's HTML: entity decoding, the misspelled accessibility label,
  the stop list, and deriving the next stop from the run
- grid clustering: merging, splitting, ordering, dominance, bounds
- pinned lines: normalising what a user types, ordering, persistence through
  user defaults, the pinned filter on the map, and the remembered pinned-only mode
- request construction, including the session cookie being optional
- the API client end to end over a stubbed `URLProtocol`
- view model behaviour: loading, filtering, failure handling and auto refresh
- the settings store: defaults, the five second floor on the refresh interval,
  and writing the language for the next launch
- the scale legend: the round distance it picks per zoom level, how long the bar
  ends up, and the switch from metres to kilometres
- the refresh countdown: progress across the interval, clamped at both ends
- vehicles that go quiet: staying on the map greyed out, leaving on the fifth
  quiet payload, coming back live, and a failed load not counting as news
- marker motion: the easing curve, half way being half way, clamping, and that a
  marker which barely moved is not worth animating
- timetables, against real bytes from the official archive: reading the zip
  central directory from a range request, extracting (and nesting) entries,
  parsing a line's JDF files, request stops, and the line-to-entry mapping being
  verified before a timetable is trusted
- the string catalogue: both languages ship, the Czech translations are the
  expected ones, and counted strings use Czech plural forms (`1 vozidlo`,
  `3 vozidla`, `12 vozidel`)

## Out of scope for now

- Route and line detail, stop timetables, vehicle history
- Translating the feed's own wording: place names, destinations and stop names
  arrive from the feed in Czech and are shown as they come
- Showing the user's own location, and any location permission
- Offline caching beyond what `URLCache` gives us

The `delay` field is displayed as reported. See `docs/api.md` for why its
meaning for some vehicles is still an open question.

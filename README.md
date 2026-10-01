# VDV Live

An iOS app that shows the live positions of buses and trains in the Vysočina
Region (Czechia) on Apple Maps.

The data comes from the public map at
`https://mapavdv.kr-vysocina.cz/`, which publishes every tracked vehicle as a
JSON array. The app polls that endpoint, draws every vehicle as a marker and
draws them on a map that is framed - and locked - to the region.

<p align="center">
  <img src="VdvLive/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="180" alt="App icon: a white bus on a blue to teal gradient">
</p>

## What it does today

- **Live map of the region.** Apple Maps, standard style, camera restricted to
  the Vysočina Region so the map cannot be panned into the sea.
- **Your own position.** The map draws the system's blue dot, with its accuracy
  ring, where you are. It is on by default and switched off in the settings. It
  needs the same permission as opening the map at your location, so iOS is not
  asked for anything unless one of the two wants it, and the position is never
  stored or sent anywhere - MapKit draws the dot and keeps it up to date.
- **Opens on the current location.** The map starts about 10 km around where you
  are, so the first thing on screen is your neighbourhood rather than a region
  seen from far out. The position is read once per launch, never leaves the
  device, and is only used when it falls inside the region the feed covers: a map
  of somewhere with no vehicles on it would be worse than the region view. The
  lock button in the header does the opposite - it remembers the viewport you are
  looking at, zoom included, and opens there from then on, which suits a commute
  you check every morning. Both are in the settings, and pressing the lock again
  forgets the viewport it saved.
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
  the marker for a single vehicle travels there over two seconds - a straight line
  at a constant speed from the position it was drawn at to the position the feed
  reports. Markers that appear or disappear are placed immediately, so only the
  ones already on screen travel. The movement is sampled 30 times a second, so
  judge it in DeviceHub: the browser mirror in `make live` shows about one frame
  per second by construction.
- **A vehicle that goes quiet is held on to.** The feed drops a vehicle for a
  payload or two before reporting it again, so a marker that stops being reported
  stays where it was last seen, drawn grey, and leaves the map only after five
  consecutive payloads without news. A greyed marker carrying a live bus is never
  drawn grey: a cluster is stale only when nothing in it is being reported. A
  failed load is not news either, so it never ages anything, and the header count
  keeps counting what the feed actually reports.
- **Grouping nearby vehicles, within a radius you choose.** Every vehicle is
  drawn on its own by default, which is what you want when you are looking for a
  particular bus. Pick a radius in the settings and buses within that distance of
  each other are drawn as one marker carrying their count instead, which is what
  makes a town centre readable. A marker shows a line number while it stands for
  one vehicle and a count while it stands for several.

  A grouped marker is a place on the map rather than a vehicle, so it holds the
  position it was drawn at and does not drift about as its members move inside
  it. It is placed afresh only when a bus joins or leaves the group, and a group
  is named after its anchor - the lowest numbered bus in it - so it keeps both its
  identity and its position for as long as it stands for the same vehicles.

  The radius is a distance on the ground, not a size on screen: raising it groups
  more, while zooming out does not group anything that a closer look would not.
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
  be turned off there), where the map opens, and the language. Czech is the
  default; English and "follow the device" are one tap away. A language change is
  written to `AppleLanguages` and shows up the next time the app is launched,
  which is what the screen says.
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
open VdvLive.xcodeproj          # or: make open
make build                     # build for the simulator
make test                      # run the unit tests
make run                       # build, install and launch on a simulator
make deploy                    # build, install and launch on a plugged-in iPhone
make launch                    # relaunch the app that is already installed
make screenshot                # save one frame of the running app
make live                      # mirror the running app into a browser tab, 1 fps
make devices                   # list simulators, then: make run SIMULATOR="iPhone 16"
make iphones                   # list the iPhones plugged into this Mac
```

`make run` installs and launches the app whether or not a Simulator window is
available. Some Xcode installations (including trimmed ones that lack
`Contents/Developer/Applications/Simulator.app`) can only run devices headlessly,
so the app is there but there is no window to look at; open the device in Xcode's
DeviceHub, or use `make screenshot` / `make live`. `make live` is a read-only
mirror, so interactions have to go through DeviceHub, Xcode or a device build.

`make deploy` does the same on a real iPhone. Four things have to be in place
first, and the first two need the Xcode application rather than the command line:

- **An Apple ID under Xcode > Settings > Accounts.** A free Apple ID is enough.
- **A team chosen for the VdvLive target**, under Signing & Capabilities, with
  "Automatically manage signing" ticked. Adding the account alone creates neither
  a certificate nor a profile - selecting the team is what does, and without it
  the build stops at `Signing for "VdvLive" requires a development team`. The
  project records the team as `DEVELOPMENT_TEAM`, so this is a one-off; use
  `make deploy TEAM=<team id>` to override it.
- **Developer Mode on the iPhone**, under Settings > Privacy & Security >
  Developer Mode, followed by a restart. Without it every device operation fails
  with "The operation failed because Developer Mode is turned off", which is also
  the state `make iphones` reports.
- **Trusting the developer on the phone** after the first install. A certificate
  from an Apple ID is not one iOS knows in advance, so the first launch is refused
  with "has not been explicitly trusted by the user" until the Apple ID is trusted
  under Settings > General > VPN & Device Management > Developer App. Also a
  one-off; `make launch` relaunches the installed app afterwards.

A free Apple ID signs for seven days at a time, so a free account means repeating
`make deploy` weekly; a paid membership extends that to a year. With several
iPhones plugged in, `make iphones` lists them and `make deploy DEVICE=<udid>` picks
one. The app id is `cz.ondralinek.VdvLive`, so with a free account that id has to be
free too. A launch that is refused is reported by `make launch` as what it is:
iOS will not open an app while the phone is locked, and it will not open one
signed by a developer it has not been told to trust.

The Xcode project uses file system synchronised groups, so new files inside
`VdvLive/` or `VdvLiveTests/` are picked up automatically - there is no `.pbxproj`
merge conflict to worry about.

If the command line tools are pointed at the Command Line Tools rather than
Xcode, `make` already passes `DEVELOPER_DIR` for you. If `xcodebuild` still
refuses to run with a licence message, accept it once:

```sh
sudo xcodebuild -license accept
```

## Project layout

```
VdvLive/
  App/            entry point and the one place that builds the live stack
  Domain/         value types: Vehicle, Traction, VehicleDelay, FavouriteLines,
                  the region, and the clusterer that turns vehicles into markers,
                  and the app settings and language
  Data/           the feed client, its request configuration, the decoder, and the
                  pinned-lines and settings stores
  Features/       the map screen, its view model, the pinned lines screen and the
                  settings screen
  DesignSystem/   colours and symbols for domain values
  Resources/      asset catalog (app icon, accent colour)
  Support/        sample data used by SwiftUI previews (#if DEBUG)
  Localizable.xcstrings   English source strings with Czech translations
VdvLiveTests/      unit tests plus JSON fixtures captured from the live feed
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
- grouping: the radius, the anchor a group is named after, ordering, dominance,
  and every vehicle ending up in exactly one marker
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

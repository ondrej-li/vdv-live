# App Store screenshots

The artwork submitted with the App Store listing, captured from a clean simulator
rather than assembled by hand:

- `iphone/` — 1206 × 2622, the 6.1"/6.3" iPhone tab
- `ipad/` — 2064 × 2752, the 13" iPad
- `watch/` — 422 × 514, Apple Watch Ultra (49 mm)

Each frame is the app itself, in Czech, with the status bar overridden to 9:41 so
the shots carry neither a clock nor a battery level.

## Regenerating

```sh
make screenshots
```

The target builds the app and the watch app, boots the simulators, installs the
app, seeds a saved map view, and takes each frame. The shots have simulators of
their own — `VDV Shot iPhone 6.3`, `VDV Shot iPad 13`, `VDV Shot Watch`, created
on the first run — so a device someone is working on, or an app it happens to
have in front, cannot end up in the artwork. Screens that need a tap to reach are
opened by debug-only launch arguments handled by
`VdvLive/App/ScreenshotRoute.swift` (`-screenshotSettings`, `-screenshotService`,
`-screenshotBoard`, …), which have no effect in a Release build, so the archive
shipped to the App Store ignores them.

The seeded preferences also switch automatic refresh off, because the countdown
hairline across the top of the map would otherwise be caught at whatever width
the capture happened to land on. The map still fetches once on launch.

Override the devices or the frames' contents when needed:

```sh
make screenshots SHOT_IPHONE="iPhone 17" SHOT_IPAD="iPad Pro 13-inch (M5)"
make screenshots SCREENSHOT_BOARD_ARGS="-screenshotBoard 'Jihlava,Hradební'"
```

The board and service frames need the timetable archive, so they download the
index (a couple of megabytes) on the first capture and reuse it afterwards.

## Checking a capture

A frame is worth looking at before it is committed. The usual accident is a
capture of the home screen instead of the app, which happens when the device is
in use or the app did not come to the front. `open screenshots/iphone/01-main.png`
is the whole check.

## Widgets

The widgets are not in this set. App Store screenshots have to be the app's own
screen at a device size, and the widgets live on the home screen, which this
target cannot place without a finger on the glass. To add one, put the widgets on
a capture device's home screen by hand and take a normal device screenshot at the
sizes above:

```sh
xcrun simctl io 'VDV Shot iPhone 6.3' screenshot screenshots/iphone/05-widgets.png
```

## A note on the timetable mapping

`VdvLive/Resources/jdf-lines.json` names the archive entries each line lives in.
The archive is republished a few times a week and reassigns those names, which
makes a shipped mapping stale: boards then find no entry for any line and come up
empty. `make mapping` rebuilds it from the published archive. If a departure
board frame comes out with no rows, run that first.

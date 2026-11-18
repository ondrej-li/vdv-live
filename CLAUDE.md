# CLAUDE.md — VDV Live

The map, not the manual. The [README](README.md) is the feature and behaviour
reference (nearly 500 lines, and worth it), [`docs/ship.md`](docs/ship.md) is the
shipping runbook, [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md) covers uploading from
CI, and `docs/` also holds `api.md`, `timetables.md`, `stop-review.md`,
`offline.md`, `share.md`, `privacy.md`, `support.md`.

## What this is

An iOS/iPadOS app showing live positions of Prague public transport vehicles, with
a watch app and a widget extension. SwiftUI, no third-party dependencies.

## Layout

```
VdvLive/              the app: Features/ (Map, Settings, Timetables…), Data/, Domain/
VdvLiveWatch/         watch app target
VdvLiveWidgets/       widget extension
VdvLiveTests/         unit tests, including AppStoreRequirementsTests
Config/               entitlements, widget Info.plist, ExportOptions.plist
deploy/, docs/        GitHub Pages site (main /docs) and the runbook
tools/                investigation scripts (Python) — see docs/stop-review.md
.github/skills/       stop-positions pipeline (Python) used when reviewing stops
Makefile              every local command; read the target list before inventing one
VdvLive.xcodeproj     committed (no XcodeGen here) — edit in Xcode or via project.pbxproj with care
```

## Building and testing

**CI is the builder.** `.github/workflows/ci.yml` runs on `macos-26`:

- **Type check and tools** — `make typecheck` (compiles app and tests without a
  simulator or signing), `py_compile` over `tools/*.py`, then a Release build for
  `generic/platform=iOS`. The Release build exists because a `#Preview` referring to
  debug-only fixtures breaks an archive and nothing else would notice.
- **Unit tests** — the simulator suite.

```sh
gh workflow run ci.yml
gh run watch
```

Required checks on `main`: **Type check and tools**, **Unit tests**.

Locally, with a full Xcode:

```sh
make build      # simulator
make test       # unit tests
make run        # build, install, launch on a simulator
make screenshots / make shots   # App Store artwork
```

Nothing here builds on Linux. Do not try to compile it on the VPS.

## Shipping

`.github/workflows/testflight.yml` archives, exports and uploads to TestFlight. A
`v*` tag uploads; a manual run uploads unless you untick the box. Six repository
secrets are needed — [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md).

`make archive` / `make upload` / `make ipa` still work on a machine with a signed-in
Xcode and a `.team` file (the Team ID, not committed). CI passes the team from
`APPLE_TEAM_ID` instead, so the two paths do not need each other.

The docs site (privacy, support, share links) is GitHub Pages from `main` / `docs`.

## Conventions

- `main` is protected: branch → PR → both checks green → squash-merge.
- Behaviour worth explaining goes in the README's sections (map, groups, pinned
  lines, widgets, watch); the tests are named after those sections.
- Anything App Store Connect checks must be enforced by
  `VdvLiveTests/AppStoreRequirementsTests.swift` rather than remembered — that file
  failing is the cheapest possible version of a rejected upload.
- The app declares iPad support (`TARGETED_DEVICE_FAMILY = "1,2"`), so layout work
  is not phone-only.
- Data sources are third-party and must stay attributed (Settings → Acknowledgements).

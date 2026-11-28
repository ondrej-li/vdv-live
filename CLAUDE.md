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
make shots        # App Store screenshots, iPhone 6.9" + iPad 13"
make shots-watch  # and the watch one
```

Nothing here builds on Linux. Do not try to compile it on the VPS.

## Shipping

**Publishing is manual; CI does not upload anything** and no Apple credential is
stored in this repository. On a machine with Xcode and a `.team` file (the Team ID,
not committed):

```sh
make check-release      # team, version, bundle ids, the identities on this Mac
make archive            # build/VdvLive.xcarchive
make upload             # …to App Store Connect, into TestFlight first
```

[`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md) has the steps and
[`docs/ship.md`](docs/ship.md) the full runbook.

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

## Before this site goes live

This repository is served publicly at https://vdv.ondralinek.cz. A change that adds or alters a
page, a form, a script, a header or a vhost passes the launch gate before it
ships:

```sh
web-launch-check https://vdv.ondralinek.cz
```

- `FAIL` blocks the publish; `WARN` is a decision to state in the reply, not
  something to leave unmentioned.
- The `web-launch-checklist` skill has the 25 items the checker cannot judge:
  privacy and terms content, colour contrast, real-device speed, spam
  protection, analytics and error monitoring, one clear call to action, and the
  signup/login/reset flows.
- Run it again after publishing: it checks the live vhost, headers and
  certificate, not the working tree.
- A preview vhost passes the same gate before DNS moves.

## Deploying this site

https://vdv.ondralinek.cz is published by the **deploy** account from this repository's
`main` branch — the `site-deploy` timer, every five minutes. Merge is
deploy: there is no publish command, and `sudo vps-site publish` refuses this
web root (one writer per root, and it is not this account).

Verify after merging, and give it up to ten minutes:

```sh
site-status --site vdv-live
curl -fsS https://vdv.ondralinek.cz/deployed.json           # {"commit": "...", "deployed_at": "..."}
git -C ~/repos/vdv-live rev-parse origin/main
```

The three commits must match. If it has not moved after two timer cycles, read
`journalctl -u site-deploy -n 50`, report the commit that should be live and the
one that is, and do not rsync into `/var/www` or edit a live file to compensate.
The `static-site-deploy` skill has the full procedure.

### The published line mapping

`/var/www/vdvlive/jdf-lines.json` is not published by `site-deploy` and not part
of the tree: `vdvlive-mapping.timer` rebuilds it hourly on the box from the
ministry's archive, because a mapping of yesterday's names points at entries that
now hold other lines. Its sources are `tools/publish-mapping.py` and
`deploy/mapping/`, installed by `make mapping-deploy` from a Mac — it is not
deployed by merging.

- A poll that cannot read the portal exits `EX_TEMPFAIL` (75) and the unit counts
  that as a completed run: the ministry's IIS server answers 500 for hours around
  a republication. Do not "fix" that by making the unit fail, and do not treat the
  resulting `deactivated` state as a fault.
- `journalctl -u vdvlive-mapping -n 30` says what the last polls saw;
  `cat /var/lib/vdvlive-mapping/state` shows how many deferrals are counted and
  whether the owner has been mailed. Past twelve deferred hours the wrapper mails
  `admin@`, once a day, and once more on recovery.
- A run that fails for a reason of ours still exits non-zero and leaves the unit
  failed. That is the one to report.

## Writing HTML and CSS

Before writing or changing HTML, CSS or client-side JavaScript here, use the
`modern-web-guidance` skill (installed for this account): search for the
capability, retrieve the guides it names, apply them. The platform usually has
the answer the library was added for — `<dialog>` and the popover API instead of
div overlays, container queries instead of media-query rewrites, View
Transitions and `@starting-style` instead of JS entrance animations, native
validation and `:user-invalid` instead of a validation library.

Browser support policy: Baseline Widely available as-is; Newly available only
with feature detection and a fallback of 20 lines or fewer, no dependencies, no
polyfills.

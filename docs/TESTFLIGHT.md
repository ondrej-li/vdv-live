# TestFlight from CI

[`docs/ship.md`](ship.md) is the shipping runbook: the app record, the review
notes, the two support URLs. This file is one part of it — how the build gets
uploaded now that nobody builds on a machine with Xcode.

[`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml) archives
VdvLive in Release, exports an `.ipa` and uploads it with the App Store Connect API
key, on a GitHub `macos-26` runner.

## How it is triggered

| Trigger | What happens |
| --- | --- |
| Push a `v*` tag | archive, export and upload |
| *Actions → TestFlight → Run workflow* | the same, unless you untick **upload** — unticked it archives, checks the archive and exports, without sending anything |

`CFBundleVersion` becomes the workflow run number, so an upload can never repeat a
build number. `MARKETING_VERSION` is `1.4.2` in the project; the Makefile's
`VERSION` variable is for local archives and CI does not use it.

The workflow also prints the archive's version, build and payloads (watch app, app
extensions) before exporting. `VdvLiveTests/AppStoreRequirementsTests.swift` covers
the things that are cheap to check in code — privacy manifest, export compliance,
icon alpha, purpose strings — this step covers the things that only exist after an
archive.

## The six repository secrets

| Secret | Contents |
| --- | --- |
| `APPLE_TEAM_ID` | `B592D69P29` |
| `APP_CONNECT_KEY_ID` | the API key's 10-character ID |
| `APP_CONNECT_ISSUER_ID` | the issuer UUID shown above the key list |
| `APP_CONNECT_KEY_P8` | the whole `AuthKey_<id>.p8`, base64 encoded |
| `BUILD_CERTIFICATE_P12` | your *Apple Distribution* certificate, base64 encoded |
| `BUILD_CERTIFICATE_PASSWORD` | the password you chose when exporting the `.p12` |

The key comes from *App Store Connect → Users and Access → Integrations → App Store
Connect API*, role **App Manager**; Apple allows one download of the `.p8`. The
certificate is the **Apple Distribution** one that enrolment mints — *Keychain
Access → My Certificates → right-click → Export*.

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
base64 -i distribution.p12      | pbcopy
```

Until all six exist the workflow fails at *Check the signing secrets exist* and names
the missing ones: a deploy that cannot deploy should be red.

## Signing

The project keeps the personal team in its build settings, which is what `make
deploy` needs for the phone on the desk. The workflow overrides it with
`DEVELOPMENT_TEAM=$APPLE_TEAM_ID` and `-allowProvisioningUpdates` plus the API key,
so the profile for the app, the widget extension and the watch app is created or
refreshed on the runner. The `.team` file used by `make archive` is irrelevant here
and stays uncommitted.

## Export options

[`Config/ExportOptions.plist`](../Config/ExportOptions.plist) is committed:
`method: app-store-connect`, `destination: export`, automatic signing for team
`B592D69P29`, symbols uploaded, no build renumbering. `make ipa` and `make upload`
still generate their own plist into `build/`, so the two paths do not interfere.

## After the upload

App Store Connect processes the build for a few minutes. The `.ipa` is kept as a
`VdvLive-ipa` artifact for 14 days, so a rejected upload can be retried without a
rebuild.

# Publishing

**CI does not publish.** There is no workflow that uploads to App Store Connect,
and no Apple credential is stored in this repository. Publishing is a manual step
from a machine with Xcode and the developer account signed in; the commit-time
workflow (`ci.yml`) only builds and tests.

Why: an upload needs a distribution identity, and an identity is a private key
Apple hands out once per certificate. Every arrangement that puts one in CI
either stores a long-lived secret (which has to be exported out of a keychain) or
re-creates the certificate per run (which mails the account holder and
invalidates profiles built on it). Neither is worth it for a handful of releases
a year.

## How to ship

__SHIP__

```sh
echo B592D69P29 > .team    # once; not committed
make check-release         # team, version, bundle ids, the identities on this Mac
make archive               # build/VdvLive.xcarchive, Release
make upload                # …to App Store Connect, into TestFlight first
```

`docs/ship.md` is the full runbook — the app record, the review notes, the two
support URLs — and the release-specific things worth knowing before review. The
watch app and the widget extension ride inside the phone app, so one archive
covers all three.

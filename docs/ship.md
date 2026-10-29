# Shipping VDV Live

What it takes to get the app into App Store Connect, through review, and onto the
store — split into the part this repository can do (`make …`) and the part only a
person with the account can do in the browser.

## What the bundle already gets right

These are easy to lose and expensive to discover at upload time, so they are
tested in `VdvLiveTests/AppStoreRequirementsTests.swift`:

| Requirement | Where |
|---|---|
| Privacy manifest, declaring `UserDefaults` with reason `CA92.1` and no tracking | `VdvLive/Resources/PrivacyInfo.xcprivacy` |
| Export compliance answered, so uploads do not stop at "Missing Compliance" | `ITSAppUsesNonExemptEncryption = NO` in the target's build settings |
| App and watch icons, single 1024 px each, no alpha channel | `Assets.xcassets/AppIcon.appiconset` |
| Location permission purpose string | `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` |
| Attributed data sources, in both languages | Settings → Acknowledgements |

## One-time setup

1. **Enrolment** in the Apple Developer Program, with the Apple ID Xcode already
   uses. That *upgrades the personal team in place*: the **Team ID usually does not
   change**, and what does is the account behind it — it can now mint App Store
   profiles, and Xcode adds an **Apple Distribution** certificate. Check with
   `make check-release`, which lists both the team ids the Mac knows and whether a
   distribution identity exists:

   ```
   team ids on this Mac:
     B592D69P29
   distribution identities:
       2) 3E666E3E... "Apple Distribution: Ondrej Linek (B592D69P29)"
   ```

2. Put the Team ID in `.team` (one line, git-ignored). If it is the one the project
   already carries, this only makes `check-release` say so; if enrolment did issue a
   new one, this is what points every target at it without touching the project:

   ```sh
   echo B592D69P29 > .team
   make check-release
   ```

3. If there is no distribution identity, **Xcode → Settings → Accounts** → the Apple
   ID → *Manage Certificates* → `+` → **Apple Distribution**. Automatic signing does
   the rest per upload.
4. **developer.apple.com → Identifiers**: `cz.ondralinek.VdvLive` and
   `cz.ondralinek.VdvLive.watchkitapp`. An upgraded team keeps the app ids it had, so
   they are normally already there; register any that are missing.
5. **App Store Connect → Business**: accept the *Free Applications* agreement. A
   free app needs no banking or tax details.
6. **App Store Connect → My Apps → +**: new app, platform iOS, primary language
   **Czech**, the bundle id above, a SKU (`vdvlive`), and a name. Names are unique
   across the store and at most 30 characters.

Once steps 1-4 are done, `make ipa` succeeds and writes a build signed with an
**iOS Team Store Provisioning Profile** good for a year — which is how you know the
account, not just the project, is set up for the store.

## Building and uploading

```sh
make check-release           # team, version, bundles, available identities
make archive                 # build/VdvLive.xcarchive, Release, for a device
make upload                  # exports and sends it to App Store Connect
make ipa                     # ...or just export the .ipa without sending it
make shots                   # iPhone 6.9" and iPad 13" screenshots
make shots-watch             # and the watch one
```

`make archive` stamps the build number from the clock (`VERSION=1.1`,
`BUILD=yyMMddHHmm`), so no upload can repeat the one before it. Override either:

```sh
make upload VERSION=1.1          # a new marketing version
make upload BUILD=42             # a specific build number
```

An archive can also be uploaded by hand: open `build/VdvLive.xcarchive` in Xcode's
Organizer and use *Distribute App → App Store Connect*.

## The upload needs an answer for, in App Store Connect

| Field | What to say |
|---|---|
| Privacy policy URL | `docs/privacy.md`, hosted — see below |
| Support URL | `docs/support.md`, hosted |
| App Privacy | **Data Not Collected** — matches the manifest exactly |
| Age rating | 4+. No objectionable content, no user-generated content, no ads |
| Price | Free, availability as you like |
| Content rights | The app shows third-party data (the region's feed, the Ministry's timetables); it has the right to, and attributes it in the app |
| Screenshots | `make shots` and `make shots-watch` |
| Review notes | Say that no account is needed, that positions come from the region's public map, and what the exclamation triangle means |

### Hosting the privacy policy and support pages

They are served from the author's own server, as a small static site generated
from this repository:

| Page | Czech (default) | English |
| --- | --- | --- |
| Landing | `https://vdv.ondralinek.cz/` | `https://vdv.ondralinek.cz/en/` |
| Privacy | `https://vdv.ondralinek.cz/privacy.html` | `https://vdv.ondralinek.cz/en/privacy.html` |
| Support | `https://vdv.ondralinek.cz/support.html` | `https://vdv.ondralinek.cz/en/support.html` |

Use the privacy and support URLs in App Store Connect.

```sh
make site          # build/site
make site-serve    # look at it on 127.0.0.1:8080
make site-deploy   # publish to the server
```

`tools/build-site.py` writes the pages and converts the screenshots from
`screenshots/`; `tools/site/style.css` is the only stylesheet. The content is in
that script, not in `docs/*.md`: each page is written once per language, and no
page is bilingual. Czech is the site root, English is under `/en/`, and the switch
in the header goes to the same page in the other tree.

The technical notes (`api.md`, `timetables.md`, `stops.md`, `offline.md`,
`ship.md`, `stop-review.md`) are still rendered by GitHub Pages from `docs/`, and
are republished on the server under `/docs/` as plain text.

The server is nginx on Debian, serving `/var/www/vdvlive`, with a Let's Encrypt
certificate that renews through `certbot.timer`. HTTP redirects to HTTPS. The site
block is kept in `deploy/nginx/vdvlive.conf` - it is the file in
`/etc/nginx/sites-available/vdvlive`; copy it there and `nginx -s reload` after
editing. Do not rewrite it from scratch: it holds the certificate paths certbot
manages, and a version without them leaves the site on port 80 only.

Pages are served `no-cache` and their assets are referenced with a content hash in
the query string (`style.css?v=…`), so a deploy is visible immediately and a
stylesheet can still be cached indefinitely.

## TestFlight, then review

1. The upload appears in **App Store Connect → TestFlight** after processing
   (minutes; occasionally up to an hour). Answer "Missing Compliance" there if it
   ever appears — it should not, the bundle answers it.
2. **Internal testing** needs no review: add yourself and test on a real device.
3. **External testing** and the App Store both go through the same submission:
   *Add for Review*, answer the contact and demo-account questions (no account
   needed), submit.
4. Review commonly takes a day or two. Rejection reasons this app should watch for
   are listed in `README.md`, under *Ship it*.

## Every release after that

- `make upload` with a build number above the last one — the Makefile does that by
  default.
- Refresh the line-to-entry mapping when timetables stop resolving: `make mapping`,
  commit the result. The archive is republished three times a week.
- Profiles for the paid team last a year; automatic signing renews them at upload.

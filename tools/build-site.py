#!/usr/bin/env python3
"""Build the VDV Live landing page and documents into a static tree.

Czech is the default language and lives at the site root; English lives under
/en/. Every page exists in exactly one language - there is no bilingual page, and
the language switch is a link to the same page in the other tree.

Screenshots come from `screenshots/` in the repository and are downscaled with
`sips`, so the site carries the same frames the App Store listing does.

    python3 tools/build-site.py --output build/site
"""

import argparse
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

ACCENT = "#0f9b8e"


# --------------------------------------------------------------------------- text

TEXT = {
    "cs": {
        "lang": "cs",
        "site": "VDV Live",
        "title": "VDV Live — vlaky a autobusy Vysočiny naživo",
        "description": "Živá mapa autobusů a vlaků Kraje Vysočina: kde právě jsou, jak jsou zpožděné a kdy odjíždějí z vaší zastávky.",
        "nav_privacy": "Soukromí",
        "nav_support": "Podpora",
        "nav_notes": "Technické poznámky",
        "switch": "English",
        "switch_href": "/en/",
        "switch_lang": "en",
        "hero_eyebrow": "Kraj Vysočina",
        "hero_title": "Vlaky a autobusy<br>Vysočiny naživo",
        "hero_lede": "Kde právě jsou, jak jsou zpožděné a kdy odjíždějí z vaší zastávky. Zdarma, bez účtu, bez reklam a bez sledování.",
        "hero_meta": "iPhone · iPad · Apple Watch",
        "hero_cta": "Podpora a časté dotazy",
        "shots_title": "Aplikace",
        "shots_lede": "Mapa, detail spoje, odjezdová tabule. Všechno v češtině, všechno funguje i offline.",
        "shot_1": "Živá mapa kraje",
        "shot_2": "Odjezdová tabule zastávky",
        "shot_3": "Nastavení a jízdní řády",
        "features_title": "Co umí",
        "f1_t": "Živá mapa kraje",
        "f1_d": "Každé vozidlo, které kraj právě hlásí, jako bod obarvený podle zpoždění. Mapa je zamčená na Vysočinu, takže se nikdy neztratíte v moři.",
        "f2_t": "Odjezdové tabule",
        "f2_d": "Vyberte zastávku a vidíte, co odsud jede: podle řádu, očekávaně a o kolik. Filtrovat lze na oblíbené linky.",
        "f3_t": "Oficiální jízdní řády",
        "f3_d": "Zastávky celého spoje s časy z archivu Ministerstva dopravy, posunuté o skutečné zpoždění. Stahují se po linkách a zůstávají v telefonu.",
        "f4_t": "Připomínky odjezdu",
        "f4_d": "Zvolte spoj, zastávku a jak dlouho předem chcete vědět. Připomínka respektuje dny, kdy spoj jede, státní svátky i konec platnosti řádu.",
        "f5_t": "Apple Watch",
        "f5_d": "Vozidla oblíbených linek na zápěstí, obarvená podle zpoždění. Hodinky si data stahují samy, telefon nepotřebují.",
        "f6_t": "Nic se nesbírá",
        "f6_d": "Bez účtu, bez analytiky, bez reklam a bez SDK třetích stran. Poloha zůstává v zařízení a nikam se neposílá.",
        "watch_title": "Na zápěstí",
        "watch_lede": "Jen to, co vás zajímá: oblíbené linky a jejich vozidla.",
        "data_title": "Odkud data pocházejí",
        "data_lede": "Aplikace je neoficiální a není spojená s krajem ani s dopravci.",
        "data_1": "Polohy vozidel",
        "data_1d": "veřejná mapa Kraje Vysočina",
        "data_2": "Jízdní řády",
        "data_2d": "Ministerstvo dopravy ČR, CC BY 4.0",
        "data_3": "Polohy zastávek",
        "data_3d": "OpenStreetMap, ODbL 1.0",
        "data_4": "Podkladová mapa",
        "data_4d": "Apple Maps",
        "footer_note": "VDV Live je neoficiální aplikace. Není spojená s Krajem Vysočina, Ministerstvem dopravy ani s žádným dopravcem.",
        "footer_contact": "Napsat autorovi",
        "privacy_title": "Zásady ochrany osobních údajů",
        "privacy_updated": "Účinné od 21. října 2026",
        "support_title": "Podpora",
        "notes_title": "Technické poznámky",
        "notes_lede": "Zápisky z průzkumu datových zdrojů. Zatím jen anglicky.",
        "back": "Zpět na úvod",
    },
    "en": {
        "lang": "en",
        "site": "VDV Live",
        "title": "VDV Live — buses and trains of Vysočina, live",
        "description": "A live map of the buses and trains of the Vysočina Region: where they are, how late they run, and when they leave your stop.",
        "nav_privacy": "Privacy",
        "nav_support": "Support",
        "nav_notes": "Technical notes",
        "switch": "Čeština",
        "switch_href": "/",
        "switch_lang": "cs",
        "hero_eyebrow": "Vysočina Region, Czechia",
        "hero_title": "Buses and trains of<br>Vysočina, live",
        "hero_lede": "Where they are right now, how late they run, and when they leave your stop. Free, no account, no ads, no tracking.",
        "hero_meta": "iPhone · iPad · Apple Watch",
        "hero_cta": "Support and common questions",
        "shots_title": "The app",
        "shots_lede": "The map, a service in detail, a stop's departure board. All in Czech and English, all working offline.",
        "shot_1": "The live map",
        "shot_2": "A stop's departure board",
        "shot_3": "Settings and timetables",
        "features_title": "What it does",
        "f1_t": "A live map of the region",
        "f1_d": "Every vehicle the region reports, coloured by how late it is. The camera is locked to Vysočina, so you cannot lose your way.",
        "f2_t": "Departure boards",
        "f2_d": "Pick a stop and see what leaves it: the timetable time, the expected one, and the delay. Narrow it to the lines you pinned.",
        "f3_t": "The official timetables",
        "f3_d": "Every stop of a run, with the times from the Ministry of Transport's archive moved by the live delay. Fetched per line, kept on the phone.",
        "f4_t": "Departure reminders",
        "f4_d": "Choose a service, a stop and how early you want to know. The reminder follows the days the service runs, public holidays, and the end of the timetable.",
        "f5_t": "Apple Watch",
        "f5_d": "The vehicles of your pinned lines on your wrist, coloured by delay. The watch fetches its own data and does not need the phone.",
        "f6_t": "Nothing is collected",
        "f6_d": "No account, no analytics, no ads, no third-party SDKs. Your position stays on the device.",
        "watch_title": "On the wrist",
        "watch_lede": "Only what you care about: your pinned lines and their vehicles.",
        "data_title": "Where the data comes from",
        "data_lede": "An unofficial app, not affiliated with the region or with any operator.",
        "data_1": "Vehicle positions",
        "data_1d": "the region's public map",
        "data_2": "Timetables",
        "data_2d": "Czech Ministry of Transport, CC BY 4.0",
        "data_3": "Stop positions",
        "data_3d": "OpenStreetMap, ODbL 1.0",
        "data_4": "Base map",
        "data_4d": "Apple Maps",
        "footer_note": "VDV Live is an unofficial app. It is not affiliated with the Vysočina Region, the Ministry of Transport or any transport operator.",
        "footer_contact": "Write to the author",
        "privacy_title": "Privacy policy",
        "privacy_updated": "Effective 21 October 2026",
        "support_title": "Support",
        "notes_title": "Technical notes",
        "notes_lede": "Notes from investigating the data sources. English only, for now.",
        "back": "Back to the start",
    },
}

# ---------------------------------------------------------------------- documents

PRIVACY = {
    "cs": [
        ("p", "VDV Live zobrazuje polohy autobusů a vlaků v Kraji Vysočina a jejich "
              "zveřejněné jízdní řády. Je to neoficiální aplikace: neprovozuje ji kraj, "
              "Ministerstvo dopravy ani žádný dopravce."),
        ("h", "Co aplikace nedělá"),
        ("ul", ["Žádný účet, žádné přihlašování, žádný profil.",
                "Žádná analytika, reklama, sledování ani hlášení pádů.",
                "Žádné osobní údaje se neshromažďují, neukládají na server, neprodávají "
                "ani nepředávají třetím stranám.",
                "Aplikace neobsahuje žádná SDK třetích stran."]),
        ("h", "Co opouští zařízení"),
        ("p", "Aplikace si vyžádá data ze dvou veřejných serverů, stejně jako by to udělal "
              "webový prohlížeč, a podkladovou mapu kreslí MapKit od Apple:"),
        ("table", [["Server", "Co se požaduje", "Proč"],
                   ["mapavdv.kr-vysocina.cz", "aktuální polohy vozidel", "mapa"],
                   ["portal.cisjr.cz", "index archivu jízdních řádů a jednotlivé linky, "
                                       "pokud si jízdní řády stáhnete",
                    "časy zastávek a doplnění linek, které živý zdroj vynechal"],
                   ["Apple (MapKit)", "dlaždice mapy a to, co MapKit ke kreslení potřebuje",
                    "podkladová mapa"]]),
        ("p", "Tyto servery nutně vidí vaši IP adresu, čas a standardní HTTP požadavek, jako "
              "každý jiný web. Aplikace k požadavkům nepřidává žádné identifikátory a historii "
              "požadavků neuchovává. Podkladovou mapou jsou Apple Maps, takže Apple vidí své "
              "vlastní požadavky podle zásad ochrany osobních údajů Applu; nic dalšího mu "
              "aplikace neposílá."),
        ("h", "Vaše poloha"),
        ("p", "Mapa se může otevřít na vaší poloze a sledovat ji. Je to volitelné a vypnuté, "
              "dokud o to nepožádáte. Poloha se čte v zařízení a slouží jen k určení středu "
              "mapy. Nikam se neposílá a nezapisuje se do logu, a neukládá se nikde jinde než "
              "v tomto zařízení: poslední použitá poloha se pamatuje, aby se mapa příště "
              "otevřela na správném místě, a zmizí spolu s aplikací."),
        ("h", "Co zůstává v zařízení"),
        ("p", "Nastavení, oblíbené linky, poslední přijaté polohy (aby mapa nezůstala "
              "prázdná, když není síť), stažené jízdní řády a nastavené připomínky jsou "
              "uložené v úložišti aplikace. Jiné aplikace je nepřečtou a smažou se společně "
              "s aplikací."),
        ("h", "Děti"),
        ("p", "Aplikace neshromažďuje údaje o nikom."),
        ("h", "Změny"),
        ("p", "Pokud se tyto zásady změní, na této adrese se objeví nová verze s novým "
              "datem účinnosti a změna bude uvedena v poznámkách k vydání."),
        ("h", "Kontakt"),
        ("p", "ondrej.linek@gmail.com"),
    ],
    "en": [
        ("p", "VDV Live shows the live positions of buses and trains in the Vysočina Region, "
              "and its published timetables. It is an unofficial app: it is not operated by "
              "the region, by the Ministry of Transport, or by any transport operator."),
        ("h", "What the app does not do"),
        ("ul", ["No account, no sign-in, no profile.",
                "No analytics, no advertising, no tracking, no crash reporting.",
                "No personal data is collected, stored on a server, sold, or shared with "
                "anyone.",
                "The app contains no third-party SDKs."]),
        ("h", "What leaves your device"),
        ("p", "Two public servers are asked for data, the same way a web browser would ask, "
              "and the base map is drawn by Apple's MapKit:"),
        ("table", [["Server", "What is requested", "Why"],
                   ["mapavdv.kr-vysocina.cz", "the current vehicle positions", "the map"],
                   ["portal.cisjr.cz", "the timetable archive's index and individual lines, "
                                       "when you download timetables",
                    "stop times, and filling in lines the live feed has dropped"],
                   ["Apple (MapKit)", "the map tiles, and what MapKit needs to draw them",
                    "the base map"]]),
        ("p", "Those servers necessarily see your IP address, the time, and the standard HTTP "
              "request, as any website does. This app adds no identifiers to those requests "
              "and keeps no history of them. The base map is Apple Maps, so Apple sees its "
              "own requests under Apple's privacy policy; the app sends Apple nothing else."),
        ("h", "Your location"),
        ("p", "The map can open on your position and follow it. That is optional and off "
              "unless you ask for it. The position is read on the device and used only to "
              "decide where the map points. It is never sent anywhere and never written to a "
              "log, and it is not kept anywhere but on this device: the last position it "
              "used is remembered so that the map can open in the right place next time, and "
              "it goes when the app does."),
        ("h", "What is kept on your device"),
        ("p", "Settings, pinned lines, the last positions received (so the map is not empty "
              "when the network is down), downloaded timetables and the reminders you set "
              "are stored inside the app's own storage. They are not readable by other apps "
              "and they go away when you delete the app."),
        ("h", "Children"),
        ("p", "The app collects nothing, from anyone."),
        ("h", "Changes"),
        ("p", "If this policy changes, the new version appears at this address with a new "
              "effective date, and the change is noted in the app's release notes."),
        ("h", "Contact"),
        ("p", "ondrej.linek@gmail.com"),
    ],
}

SUPPORT = {
    "cs": [
        ("p", 'Napište na <a href="mailto:ondrej.linek@gmail.com">ondrej.linek@gmail.com</a> '
              '— chyby, dotazy i nápady. Chyby a nápady můžete zadat i jako '
              '<a href="https://github.com/ondrej-li/vdv-live/issues">issue na GitHubu</a>.'),
        ("h", "Linka chybí na mapě"),
        ("p", "Aplikace ukazuje to, co kraj zveřejňuje. Zdroj na část dne o některých linkách "
              "mlčí a taková linka na mapě není."),
        ("p", "Pokud máte stažené jízdní řády (Nastavení → Jízdní řády) a zapnuté "
              "<em>Doplnit linky, které zdroj vynechává</em>, aplikace dokreslí linky, které "
              "podle řádu jet mají, i když zdroj nehlásí nic. Takový bod je <strong>přerušovaný "
              "oranžový s vykřičníkem</strong>, u zastávky, kam spoj podle řádu míří. Je to "
              "zveřejněná zastávka, ne měření, takže se nehýbe a nedá se vybrat."),
        ("h", "Co znamená vykřičník"),
        ("p", "Přesně to: poloha je spočítaná z jízdního řádu a z dodaných poloh zastávek, "
              "ne přijatá z vozidla. Je to místo, kde by autobus měl být, ne kde byl viděn."),
        ("h", "Jízdní řád není k dispozici"),
        ("p", "Nastavení → Jízdní řády stáhne index (pár megabajtů) a pak jednotlivé linky "
              "podle potřeby, po kilobajtech; všechno zůstává v telefonu, takže to funguje "
              "i offline. Pokud linka i potom hlásí, že řád není k dispozici, archiv byl "
              "přegenerován a seznam linek v aplikaci je zastaralý: klepněte na "
              "<strong>Zkontrolovat aktualizace</strong>. Pokud to nepomůže, oprava přijde "
              "s další verzí aplikace."),
        ("h", "Připomínka nepřijde"),
        ("p", "Připomínku nastavíte na odjezdové tabuli zastávky: u odjezdu klepněte na "
              "zvonek, zvolte, jak dlouho předem chcete vědět, a vypněte dny, kdy necestujete. "
              "Přehled a smazání jsou v Nastavení → Připomínky."),
        ("ul", ['Zkontrolujte, že iOS aplikaci povoluje oznámení (pokud ne, aplikace to '
                'napíše v přehledu připomínek).',
                'Zkontrolujte, že je stažený jízdní řád dané linky v Nastavení → Jízdní '
                'řády: připomínka se počítá z řádu, takže bez něj naplánovat nelze.',
                'Připomínka se řídí <strong>časem v jízdním řádu</strong>. Na zpožděný spoj '
                'se nečeká; živé zpoždění ukáže aplikace při příštím otevření.']),
        ("p", "Na rozdíl od zbytku aplikace se připomínka počítá v telefonu ze staženého "
              "řádu, takže dorazí i při zavřené aplikaci."),
        ("h", "Mapa zešedne"),
        ("p", "Šedé body znamenají, že o vozidlech aplikace od poslední aktualizace neslyšela "
              "— obvykle ztráta spojení. Když se zdroj nedá načíst, horní řádek místo počtu "
              "vozidel ukazuje <code>Offline · last 12:34</code>. Poloha z před hodiny není "
              "mapa, proto je šedá."),
        ("h", "Nahlášení chyby"),
        ("p", "V hlášení pomůže: verze aplikace a iOS, co jste dělali, co jste čekali a co se "
              "stalo, a pokud to jde, snímek obrazovky."),
    ],
    "en": [
        ("p", 'Write to <a href="mailto:ondrej.linek@gmail.com">ondrej.linek@gmail.com</a> '
              '— bug reports, questions, and feature requests. Bugs and ideas are welcome as '
              'an <a href="https://github.com/ondrej-li/vdv-live/issues">issue on GitHub</a> '
              'as well.'),
        ("h", "A line is missing from the map"),
        ("p", "The app shows what the regional feed publishes. The feed goes quiet about whole "
              "lines for stretches of the day, and when it does, the line is not on the map."),
        ("p", "If you have downloaded the timetables (Settings → Timetables) and switched on "
              "<em>Fill in lines the feed leaves out</em>, the app draws lines the timetable "
              "says should be running even when the feed reports nothing. Those markers are "
              "drawn as a <strong>dashed amber capsule with an exclamation triangle</strong>, "
              "at the stop the service is due at. That position is the published stop, not a "
              "measurement, so it does not move and cannot be selected."),
        ("h", "What the exclamation triangle means"),
        ("p", "Exactly that: the position was calculated from the timetable and the shipped "
              "stop positions, not received from the vehicle. It is a place the bus should "
              "be, not a place it was seen."),
        ("h", "Timetables are not available"),
        ("p", "Settings → Timetables downloads an index (a couple of megabytes) and then each "
              "line's timetable on demand, a few kilobytes at a time; everything is kept on "
              "the phone afterwards, so it works offline. If a line still says its timetable "
              "is not available, the published archive has been rebuilt and the app's line "
              "list is out of date: tap <strong>Check for updates</strong>, and if that does "
              "not help, the fix comes with the next release of the app."),
        ("h", "A reminder does not arrive"),
        ("p", "A reminder is set on a stop's departure board: tap the bell next to a "
              "departure, choose how early you want to know, and turn off the days you do not "
              "travel. Settings → Reminders lists them and deletes them."),
        ("ul", ["Check that iOS is allowed to notify you - the reminders screen says so if it "
                "is not.",
                "Check that the line's timetable has been downloaded, under Settings → "
                "Timetables: a reminder is worked out from the timetable, so a line with no "
                "timetable on the phone cannot be scheduled.",
                "Remember the warning follows the <strong>timetable's</strong> time. A late "
                "bus is not waited for; the app shows the live delay the next time you open "
                "it."]),
        ("p", "Unlike the rest of the app, a reminder is worked out on the phone from the "
              "downloaded timetable, so it arrives even when the app is closed."),
        ("h", "The map goes grey"),
        ("p", "Grey markers mean the app has not heard from those vehicles since it last "
              "refreshed - usually a lost connection. When the feed cannot be reached, the "
              "status line says <code>Offline · last 12:34</code> in place of the vehicle "
              "count. A position from an hour ago is not the map, so it is drawn grey rather "
              "than passed off as current."),
        ("h", "Reporting a bug"),
        ("p", "Useful in a report: the app version and the iOS version, what you did, what "
              "you expected and what happened, and a screenshot if you have one."),
    ],
}

NOTES = [
    ("api.html", "The vehicle feed", "What the regional endpoint returns, and the quirks it carries."),
    ("timetables.html", "The timetable archive", "How the Ministry's JDF archive is read without downloading 106 MB."),
    ("stops.html", "Stop positions", "Where stop coordinates come from when the region publishes none."),
    ("offline.html", "Offline behaviour", "What is kept, and why a stale position is drawn grey."),
    ("ship.html", "Shipping", "What the bundle has to get right before an upload."),
    ("stop-review.html", "Stop review", "How the shipped stop table was checked."),
]


# ------------------------------------------------------------------------ helpers

def esc(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def depth(prefix):
    return "../" if prefix else ""


def head(lang, title, description, canonical, assets, alt_cs, alt_en):
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<meta name="description" content="{esc(description)}">
<meta name="theme-color" content="#07100f">
<link rel="canonical" href="{canonical}">
<link rel="alternate" hreflang="cs" href="{alt_cs}">
<link rel="alternate" hreflang="en" href="{alt_en}">
<link rel="alternate" hreflang="x-default" href="{alt_cs}">
<link rel="icon" href="{assets}assets/icon-300.png" type="image/png">
<link rel="apple-touch-icon" href="{assets}assets/icon-300.png">
<link rel="stylesheet" href="{assets}assets/style.css">
</head>"""


class Page:
    """Where a page sits, so every link on it can be written correctly.

    Links are relative, because the site is served from a domain root now and may
    not be later. `nav` is the path to sibling pages, `assets` to the shared files,
    and `docs` to the English technical notes.
    """

    def __init__(self, lang, stem, nav, assets, docs, switch_href, switch_lang):
        self.lang = lang
        self.stem = stem
        self.nav = nav
        self.assets = assets
        self.docs = docs
        self.switch_href = switch_href
        self.switch_lang = switch_lang


def page_for(lang, stem):
    """The Czech tree is the site root; English is one level down."""
    if lang == "cs":
        return Page("cs", stem, nav="", assets="",
                    docs="docs/api.html",
                    switch_href="/en/" if stem == "index" else f"/en/{stem}.html",
                    switch_lang="en")
    return Page("en", stem, nav="", assets="../",
                docs="../docs/api.html",
                switch_href="/" if stem == "index" else f"/{stem}.html",
                switch_lang="cs")


def header(t, page):
    nav = []
    for stem, label in (("privacy", t["nav_privacy"]), ("support", t["nav_support"])):
        cls = ' class="on"' if stem == page.stem else ""
        nav.append(f'<a href="{page.nav}{stem}.html"{cls}>{esc(label)}</a>')
    return f"""<header class="site">
  <div class="wrap">
    <a class="brand" href="{page.nav}{'index.html' if page.stem != 'index' else './'}">
      <img src="{page.assets}assets/icon-300.png" alt="" width="34" height="34">
      <span>{esc(t['site'])}</span>
    </a>
    <nav>{''.join(nav)}<a class="lang" href="{page.switch_href}" hreflang="{page.switch_lang}">{esc(t['switch'])}</a></nav>
  </div>
</header>"""


def footer(t, page):
    return f"""<footer class="site">
  <div class="wrap">
    <p class="muted">{esc(t['footer_note'])}</p>
    <p class="muted links">
      <a href="{page.nav}privacy.html">{esc(t['nav_privacy'])}</a>
      <a href="{page.nav}support.html">{esc(t['nav_support'])}</a>
      <a href="{page.docs}">{esc(t['nav_notes'])}</a>
      <a href="mailto:ondrej.linek@gmail.com">{esc(t['footer_contact'])}</a>
    </p>
  </div>
</footer>
</body>
</html>"""


def render_blocks(blocks):
    out = []
    for block in blocks:
        kind = block[0]
        if kind == "h":
            out.append(f"<h2>{esc(block[1])}</h2>")
        elif kind == "p":
            out.append(f"<p>{block[1]}</p>")
        elif kind == "ul":
            items = "".join(f"<li>{item}</li>" for item in block[1])
            out.append(f"<ul>{items}</ul>")
        elif kind == "table":
            rows = block[1]
            head_row = "".join(f"<th>{esc(c)}</th>" for c in rows[0])
            body = "".join(
                "<tr>" + "".join(f"<td>{esc(c)}</td>" for c in row) + "</tr>"
                for row in rows[1:]
            )
            out.append(f"<div class=\"table\"><table><thead><tr>{head_row}</tr></thead>"
                       f"<tbody>{body}</tbody></table></div>")
    return "\n".join(out)


def doc_page(lang, t, stem, title, updated, blocks, canonical_base):
    page = page_for(lang, stem)
    tree = "" if lang == "cs" else "en/"
    canonical = f"{canonical_base}{tree}{stem}.html"
    other = "" if lang == "en" else "en/"
    body = f"""<body class="doc">
{header(t, page)}
<main class="wrap narrow">
  <h1>{esc(title)}</h1>
  <p class="updated">{esc(updated)}</p>
  {render_blocks(blocks)}
  <p class="back"><a href="{page.nav}index.html">← {esc(t['back'])}</a></p>
</main>
{footer(t, page)}"""
    return head(lang, f"{title} — {t['site']}", t["description"], canonical,
                page.assets, f"{canonical_base}{stem}.html",
                f"{canonical_base}en/{stem}.html") + "\n" + body


# --------------------------------------------------------------------------- pages

def landing(lang, t, canonical_base):
    page = page_for(lang, "index")
    prefix = page.nav
    assets = page.assets
    canonical = canonical_base if lang == "cs" else f"{canonical_base}en/"
    alt_cs = canonical_base
    alt_en = f"{canonical_base}en/"

    shots = [
        ("iphone-01-main.jpg", t["shot_1"]),
        ("iphone-04-departure-board.jpg", t["shot_2"]),
        ("iphone-02-settings.jpg", t["shot_3"]),
    ]
    shot_html = "".join(
        f"""<figure class="phone"><img src="{assets}assets/shots/{name}" alt="{esc(cap)}"
             width="620" loading="lazy"><figcaption>{esc(cap)}</figcaption></figure>"""
        for name, cap in shots
    )

    features = "".join(
        f"""<article><h3>{esc(t[f'{n}_t'])}</h3><p>{esc(t[f'{n}_d'])}</p></article>"""
        for n in ("f1", "f2", "f3", "f4", "f5", "f6")
    )

    sources = "".join(
        f"""<li><strong>{esc(t[f'data_{n}'])}</strong><span>{esc(t[f'data_{n}d'])}</span></li>"""
        for n in ("1", "2", "3", "4")
    )

    body = f"""<body>
{header(t, page)}
<main>
  <section class="hero">
    <div class="glow"></div>
    <div class="wrap hero-inner">
      <img class="app-icon" src="{assets}assets/icon-300.png" alt="" width="96" height="96">
      <p class="eyebrow">{esc(t['hero_eyebrow'])}</p>
      <h1>{t['hero_title']}</h1>
      <p class="lede">{esc(t['hero_lede'])}</p>
      <p class="meta">{esc(t['hero_meta'])}</p>
      <p class="cta"><a class="button" href="{page.nav}support.html">{esc(t['hero_cta'])}</a></p>
    </div>
  </section>

  <section class="shots">
    <div class="wrap">
      <h2>{esc(t['shots_title'])}</h2>
      <p class="lede">{esc(t['shots_lede'])}</p>
      <div class="shot-row">{shot_html}</div>
    </div>
  </section>

  <section class="features">
    <div class="wrap">
      <h2>{esc(t['features_title'])}</h2>
      <div class="grid">{features}</div>
    </div>
  </section>

  <section class="watch">
    <div class="wrap split">
      <div>
        <h2>{esc(t['watch_title'])}</h2>
        <p class="lede">{esc(t['watch_lede'])}</p>
      </div>
      <figure class="watch-figure">
        <img src="{assets}assets/shots/watch-main.jpg" alt="VDV Live on Apple Watch"
             width="420" loading="lazy">
      </figure>
    </div>
  </section>

  <section class="data">
    <div class="wrap">
      <h2>{esc(t['data_title'])}</h2>
      <p class="lede">{esc(t['data_lede'])}</p>
      <ul class="sources">{sources}</ul>
    </div>
  </section>
</main>
{footer(t, page)}"""

    return head(lang, t["title"], t["description"], canonical, assets,
                alt_cs, alt_en) + "\n" + body


def build(output: pathlib.Path):
    output = output.resolve()
    if output.exists():
        shutil.rmtree(output)
    (output / "assets" / "shots").mkdir(parents=True)
    (output / "en").mkdir()
    (output / "docs").mkdir()

    # Images: the same frames the App Store listing uses, sized for the web.
    conversions = [
        ("screenshots/iphone/01-main.png", "assets/shots/iphone-01-main.jpg", 620),
        ("screenshots/iphone/03-service-timetable.png", "assets/shots/iphone-03-service-timetable.jpg", 620),
        ("screenshots/iphone/04-departure-board.png", "assets/shots/iphone-04-departure-board.jpg", 620),
        ("screenshots/iphone/02-settings.png", "assets/shots/iphone-02-settings.jpg", 620),
        ("screenshots/watch/01-main.png", "assets/shots/watch-main.jpg", 420),
    ]
    have_sips = shutil.which("sips") is not None
    for source, target, width in conversions:
        src = ROOT / source
        if have_sips and src.exists():
            subprocess.run(["sips", "-Z", str(width), "-s", "format", "jpeg",
                            "-s", "formatOptions", "82", str(src),
                            "--out", str(output / target)],
                           check=True, capture_output=True)
        else:
            shutil.copy(src, output / target)

    icon = ROOT / "VdvLive/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    if have_sips:
        subprocess.run(["sips", "-Z", "300", str(icon), "--out",
                        str(output / "assets" / "icon-300.png")],
                       check=True, capture_output=True)
    else:
        shutil.copy(icon, output / "assets" / "icon-300.png")

    shutil.copy(ROOT / "tools" / "site" / "style.css", output / "assets" / "style.css")
    shutil.copy(output / "assets" / "icon-300.png", output / "favicon.ico")

    base = "https://vdv.ondralinek.cz/"
    for lang in ("cs", "en"):
        t = TEXT[lang]
        prefix = "" if lang == "cs" else "en/"
        directory = output / prefix
        (directory / "index.html").write_text(landing(lang, t, base), encoding="utf-8")
        for stem, blocks, title_key, updated_key in (
            ("privacy", PRIVACY[lang], "privacy_title", "privacy_updated"),
            ("support", SUPPORT[lang], "support_title", None),
        ):
            updated = t[updated_key] if updated_key else ""
            (directory / f"{stem}.html").write_text(
                doc_page(lang, t, stem, t[title_key], updated, blocks, base),
                encoding="utf-8",
            )

    # Technical notes: English only, at the paths they were already published under.
    notes_dir = ROOT / "docs"
    t = TEXT["en"]
    note_t = dict(t)
    note_t["switch_href"] = "/"
    note_t["switch_lang"] = "cs"
    for name, title, blurb in NOTES:
        source = notes_dir / name.replace(".html", ".md")
        if not source.exists():
            continue
        # The notes are rendered by the Jekyll theme on GitHub Pages; here they are
        # shown as plain preformatted text so the site has no build dependency.
        text = source.read_text(encoding="utf-8")
        note_page = Page("en", "notes", nav="../", assets="../", docs="api.html",
                         switch_href="/", switch_lang="cs")
        body = f"""<body class="doc">
{header(note_t, note_page)}
<main class="wrap narrow">
  <h1>{esc(title)}</h1>
  <p class="updated">{esc(blurb)}</p>
  <pre class="markdown">{esc(text)}</pre>
  <p class="back"><a href="/">← {esc(note_t['back'])}</a></p>
</main>
{footer(note_t, note_page)}"""
        (output / "docs" / name).write_text(
            head("en", f"{title} — {note_t['site']}", blurb,
                 f"{base}docs/{name}", "../", f"{base}", f"{base}en/")
            + "\n" + body,
            encoding="utf-8",
        )

    print(f"built {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=str(ROOT / "build" / "site"))
    build(pathlib.Path(parser.parse_args().output))

"""Add the Czech strings the departure boards need.

Xcode writes the catalogue itself, so this script only adds what is missing and leaves
the existing order alone: a re-sorted file would show up as a large diff for no reason.
"""

import json

PATH = "VdvLive/Localizable.xcstrings"

# English (the source) -> Czech. Plural forms are given as a dict of
# "one"/"few"/"other", which is how a String Catalog stores them.
TRANSLATIONS = {
    "Departures and arrivals": "Odjezdy a příjezdy",
    "Done": "Hotovo",
    "Timetables not downloaded": "Jízdní řády nejsou staženy",
    "The board is read from the line timetables, which have to be downloaded once.":
        "Tabule se sestavuje z jízdních řádů linek, ty je potřeba jednou stáhnout.",
    "Download timetables": "Stáhnout jízdní řády",
    "Nothing due": "Nic nejede",
    "No service calls here between an hour ago and three hours from now.":
        "V této zastávce nezastavuje žádný spoj od hodiny zpět do tří hodin dopředu.",
    "Line": "Linka",
    "Scheduled": "Podle řádu",
    "Expected": "Očekáváno",
    "Delay": "Zpoždění",
    "Reading %lld lines…": {
        "one": "Načítám %lld linku…",
        "few": "Načítám %lld linky…",
        "other": "Načítám %lld linek…",
    },
    "Remove from starred stops": "Odebrat z oblíbených zastávek",
    "Star this stop": "Přidat zastávku k oblíbeným",
    "Starred stops": "Oblíbené zastávky",
    "No starred stops yet.": "Zatím žádné oblíbené zastávky.",
    "Tap a stop for its departures. Swipe to remove.":
        "Klepnutím na zastávku zobrazíte odjezdy. Přejetím doleva ji odeberete.",
    "Add a stop": "Přidat zastávku",
    "Search by name": "Hledat podle názvu",
    "Stops can also be starred from the board, after tapping their flag on the map.":
        "Zastávku můžete přidat k oblíbeným i z tabule po klepnutí na její vlaječku v mapě.",
    "Departure boards for the stops you watch": "Odjezdové tabule vašich zastávek",
    "Stop departure boards": "Odjezdové tabule zastávek",
    "Stops": "Zastávky",
    "expected %@": "očekáváno %@",
    "not departed yet": "ještě neodjelo",
    "Line %@, scheduled %@, %@, %@": "Linka %@, podle řádu %@, %@, %@",
    "At departure": "V době odjezdu",
    "Notifications": "Upozornění",
    "Schedule": "Jízdní řád",
    "Timetable until": "Jízdní řád do",
    "Next notification": "Další oznámení",
    "Not on these days": "V tyto dny nic",
    "Until the next timetable change": "Do změny jízdních řádů",
    "working days": "pracovní dny",
    "weekends": "víkendy",
    "Sundays": "neděle",
    "Sundays and public holidays": "neděle a svátky",
    "every day": "každý den",
    "Warn me before a service reaches my stop": "Upozornit před příjezdem spoje na moji zastávku",
    "Reading services…": "Načítám spoje…",
    "Stop": "Zastávka",
    "Service": "Spoj",
    "Departs": "Odjíždí",
    "Runs": "Jezdí",
    "A day the service does not run on, or a public holiday, is left out on its own.":
        "Den, kdy spoj nejede, nebo státní svátek se vynechá sám.",
    "Notifications are turned off for this app, so nothing can arrive. Turn them on in the system settings.":
        "Oznámení jsou pro tuto aplikaci vypnutá, takže nic nedorazí. Zapněte je v nastavení systému.",
    "Line %@ has no timetable on this device, so its notifications cannot be scheduled.":
        "Linka %@ nemá v zařízení jízdní řád, takže její oznámení nelze naplánovat.",
    "Add notification": "Přidat upozornění",
    "Tap + to add a notification.": "Klepnutím na + přidáte upozornění.",
    "Search stops": "Hledat zastávky",
    "Select stop": "Vybrat zastávku",
    "Select line": "Vybrat linku",
    "Select service": "Vybrat spoj",
    "Customize": "Přizpůsobit",
    "Loading timetable…": "Načítám jízdní řád…",
    "No lines at this stop": "V této zastávce nejsou linky",
    "No line is listed for this stop.": "Pro tuto zastávku není uvedena žádná linka.",
    "No timetable is available for this line.": "Pro tuto linku není dostupný jízdní řád.",
    "No services at this stop": "V této zastávce nejsou spoje",
    "This line has no timed service calling at the selected stop.":
        "Na této lince v této zastávce nezastavuje žádný časovaný spoj.",
    "Notify me": "Upozornit",
    "How far ahead": "S jakým předstihem",
    "Exclude days": "Vynechat dny",
    "Download timetables in Settings before adding a notification.":
        "Před přidáním upozornění stáhněte jízdní řády v Nastavení.",
    "Unable to load timetables": "Jízdní řády se nepodařilo načíst",
    "%lld min before": {
        "one": "%lld minutu předem",
        "few": "%lld minuty předem",
        "other": "%lld minut předem",
    },
    "Missing timetables": "Chybějící jízdní řády",
    "Line %@ · service %@": "Linka %@ · spoj %@",
    "%@ from %@": "%@ ze zastávky %@",
    "service %@": "spoj %@",
    "Search": "Hledat",
    "Lines": "Linky",
    "Lines in the archive": "Linek v archivu",
    "Stations": "Zastávky",
    "Reload": "Obnovit",
    "Show the whole region": "Zobrazit celý kraj",
    "Line number or stop name": "Číslo linky nebo název zastávky",
    "Type a line number, such as 420, or the name of a stop.":
        "Zadejte číslo linky, například 420, nebo název zastávky.",
    "Nothing matches “%@”.": "Nic neodpovídá „%@“.",
    "Saved view": "Uložený výřez",
    "Remembers the part of the map and the zoom you are looking at now, and opens there next time. Turning it off forgets it.":
        "Zapamatuje si část mapy a přiblížení, které právě vidíte, a příště se otevře tam. Vypnutím se zapomenou.",
    "The position is read on the device and never sent anywhere. The blue dot is the system's own, and following keeps the map centred on it while you move.":
        "Poloha se čte v zařízení a nikam se neposílá. Modrý bod je systémový a sledování drží mapu vycentrovanou na něm, když se pohybujete.",
    "No pinned lines yet. Pin a line number in the Lines screen, or tap a vehicle on the map and use its star.":
        "Zatím žádné oblíbené linky. Přidejte číslo linky na obrazovce Linky nebo klepněte na vozidlo v mapě a použijte jeho hvězdičku.",
    "Show all lines": "Zobrazit všechny linky",
    "Show only pinned lines": "Zobrazit jen oblíbené linky",
    "No pinned lines here": "Žádné oblíbené linky",
    "None of the lines that call at this stop is one you pinned.":
        "Touto zastávkou neprojíždí žádná z vašich oblíbených linek.",
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def czech(value):
    if isinstance(value, dict):
        return {"variations": {"plural": {count: unit(text) for count, text in value.items()}}}
    return unit(value)


def main():
    with open(PATH) as handle:
        document = json.load(handle)

    strings = document["strings"]
    added = []
    for key, value in TRANSLATIONS.items():
        entry = strings.setdefault(key, {})
        localizations = entry.setdefault("localizations", {})
        if "cs" in localizations:
            continue
        localizations["cs"] = czech(value)
        added.append(key)

    with open(PATH, "w") as handle:
        handle.write(xcode_style(json.dumps(document, ensure_ascii=False, indent=2,
                                        separators=(",", " : "))))
        handle.write("\n")

    print("added %d Czech strings, catalogue now %d keys" % (len(added), len(strings)))


def xcode_style(text):
    """Xcode writes an empty entry as a brace pair with a blank line between them.

    `json.dumps` collapses it to `{}`, which would rewrite thirteen untouched keys and
    bury the real change in the diff.
    """
    lines = []
    for line in text.split("\n"):
        stripped = line.rstrip()
        if stripped.endswith(": {},") or stripped.endswith(": {}"):
            indent = line[:len(line) - len(line.lstrip())]
            comma = "," if stripped.endswith(": {} ,".strip()) or stripped.endswith(": {},") else ""
            lines.append(stripped[: -len("{}" + comma)] + "{")
            lines.append("")
            lines.append(indent + "}" + comma)
            continue
        lines.append(line)
    return "\n".join(lines)


if __name__ == "__main__":
    main()

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
    "Reminders": "Připomínky",
    "Remind me": "Připomenout",
    "Warn me": "Upozornit",
    "At departure": "V době odjezdu",
    "%lld min before": {
        "one": "%lld minutu předem",
        "few": "%lld minuty předem",
        "other": "%lld minut předem",
    },
    "Days": "Dny",
    "Turn off a day you do not travel. A day the service does not run on, or a public holiday, is left out on its own.":
        "Vypněte den, kdy necestujete. Den, kdy spoj nejede, nebo státní svátek se vynechá sám.",
    "The warning is about the timetable's own time. A late bus is not waited for: the notification arrives when the timetable says it should, and the app shows the live delay next time it is opened.":
        "Upozornění vychází z času v jízdním řádu. Na zpožděný spoj se nečeká: připomínka přijde včas podle řádu a živé zpoždění ukáže aplikace při příštím otevření.",
    "The timetable is published until %@.": "Jízdní řád je zveřejněn do %@.",
    "New reminder": "Nová připomínka",
    "Reminder": "Připomínka",
    "Delete reminder": "Smazat připomínku",
    "No reminders yet. Open a stop's board and tap the bell next to a departure.":
        "Zatím žádné připomínky. Otevřete tabuli zastávky a klepněte na zvonek u odjezdu.",
    "Notifications are turned off for this app, so no reminder can arrive. Turn them on in the system settings.":
        "Oznámení jsou pro tuto aplikaci vypnutá, takže žádná připomínka nedorazí. Zapněte je v nastavení systému.",
    "Line %@ has no timetable on this device, so its reminders cannot be scheduled.":
        "Linka %@ nemá v zařízení jízdní řád, takže její připomínky nelze naplánovat.",
    "Missing timetables": "Chybějící jízdní řády",
    "Reminders are worked out from the downloaded timetables, so they follow the service's own days: no weekends on a school run, no public holidays, and nothing after the timetable ends.":
        "Připomínky se počítají ze stažených jízdních řádů, takže respektují dny spoje: školní spoj nejezdí o víkendu ani o svátcích a po konci platnosti řádu se nic nenaplánuje.",
    "Line %@ · service %@": "Linka %@ · spoj %@",
    "%@ from %@": "%@ ze zastávky %@",
    "Warnings before a service reaches your stop": "Upozornění před příjezdem spoje na vaši zastávku",
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

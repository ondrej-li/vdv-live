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

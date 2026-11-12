"""Add the Czech strings the timetable browser and the new diagnostics need.

Xcode writes the catalogue itself, so this script only adds what is missing and
leaves the existing order alone: a re-sorted file would show up as a large diff for
no reason. Run it once after changing the screens:

    python3 tools/add-timetable-browser-strings.py
"""

import json

PATH = "VdvLive/Localizable.xcstrings"

# English (the source) -> Czech.
TRANSLATIONS = {
    # The browse screen
    "Downloaded lines": "Stažené linky",
    "No line is on this phone yet": "V telefonu zatím není žádná linka",
    "A line is downloaded the first time something needs it: a vehicle's card, a stop's board, or the setting that fills in lines the feed leaves out.":
        "Linka se stáhne, jakmile ji něco potřebuje: karta vozidla, tabule zastávky nebo volba, která doplňuje linky, o kterých mlčí poloha.",
    "One row per line whose timetable can be read without the network.":
        "Řádek pro každou linku, jejíž jízdní řád jde přečíst i bez sítě.",
    "Files on disk": "Soubory na disku",
    "The archive entry each line was read out of. The ministry renumbers these names every time it republishes, so a file can declare a different line than the one it was downloaded for.":
        "Položka archivu, ze které se linka četla. Ministerstvo při každém zveřejnění tato jména přečísluje, takže soubor může hlásit jinou linku, než pro kterou se stáhl.",
    "Line or route": "Linka nebo trasa",
    "Lines": "Linky",
    "%lld runs": {
        "one": "%lld spoj",
        "few": "%lld spoje",
        "other": "%lld spojů",
    },
    "%lld stops": {
        "one": "%lld zastávka",
        "few": "%lld zastávky",
        "other": "%lld zastávek",
    },
    "declares %@": "hlásí %@",
    "reads %@": "čte %@",
    "no line reads it": "nečte ji žádná linka",
    "not readable": "nelze přečíst",
    "not in the index": "není v indexu",

    # One line
    "Timetable": "Jízdní řád",
    "Route": "Trasa",
    "Operator": "Dopravce",
    "Valid": "Platnost",
    "Departs": "Odjezdy",
    "Archive entry": "Položka archivu",
    "Source files": "Zdrojové soubory",
    "This copy came from an earlier publication of the archive: the entry it lives in has since been renumbered, so it is read from the file cached on this phone. It is still a timetable, but it may have been replaced.":
        "Tato kopie pochází z dřívějšího zveřejnění archivu: položka, ve které bydlí, byla od té doby přečíslována, takže se čte ze souboru uloženého v telefonu. Pořád je to jízdní řád, ale mohl být nahrazen.",
    "The JDF tables inside the archive entry, exactly as the ministry published them.":
        "Tabulky JDF uvnitř položky archivu, přesně jak je ministerstvo zveřejnilo.",
    "One row per service of the line, in the order they leave the first stop.":
        "Řádek pro každý spoj linky, v pořadí, v jakém vyjíždějí z první zastávky.",
    "Run %@": "Spoj %@",
    "This run does not serve this stop": "Tento spoj zde nezastavuje",
    "A stop with no time is a request stop, which the timetable marks with a symbol rather than a time.":
        "Zastávka bez času je zastávka na znamení, kterou jízdní řád značí symbolem místo času.",
    "(empty)": "(prázdné)",
    "Copy": "Kopírovat",
    "from %@": "od %@",
    "until %@": "do %@",
    "Runs": "Spoje",
    "Stops of each run": "Zastávky spojů",
    "Stop to line": "Zastávka a linka",
    "Calendar exceptions": "Výjimky v kalendáři",
    "Operators": "Dopravci",
    "Fixed codes": "Pevné kódy",
    "Format version": "Verze formátu",
    "Header": "Hlavička",
    "Connections": "Návaznosti",
    "Table": "Tabulka",

    # The mapping's identity
    "Built for": "Postaveno pro",
    "Matches the index": "Odpovídá indexu",
    "Not recorded": "Neuvedeno",
    "Cannot be told": "Nelze určit",
    "Yes": "Ano",
    "No - stale": "Ne – zastaralé",
    "The mapping names entries of an older archive than the index on this phone, so every line will look \"not in the published timetable\" until it is refreshed.":
        "Mapování ukazuje na položky staršího archivu, než jaký je v telefonu, takže každá linka bude do obnovení vypadat jako „není ve zveřejněném jízdním řádu“.",
    "Browse what was downloaded": "Procházet stažené",
    "Readable lines": "Čitelné linky",
    "Every archive entry file the app keeps, the line it declares in its own tables, and the line that reads it today. A file whose declared line has no reader was cached for an archive the mapping no longer describes.":
        "Každý soubor položky archivu, který aplikace drží, linka, kterou hlásí ve svých tabulkách, a linka, která ho dnes čte. Soubor, jehož linku nikdo nečte, se uložil pro archiv, který mapování už nepopisuje.",
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
    """Xcode writes an empty entry as a brace pair with a blank line between them."""
    lines = []
    for line in text.split("\n"):
        stripped = line.rstrip()
        if stripped.endswith(": {},") or stripped.endswith(": {}"):
            indent = line[:len(line) - len(line.lstrip())]
            comma = "," if stripped.endswith(": {},") else ""
            lines.append(stripped[: -len("{}" + comma)] + "{")
            lines.append("")
            lines.append(indent + "}" + comma)
            continue
        lines.append(line)
    return "\n".join(lines)


if __name__ == "__main__":
    main()

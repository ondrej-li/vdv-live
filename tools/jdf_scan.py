#!/usr/bin/env python3
"""Map JDF archive entries to line numbers and count the Vysočina subset.

Answers three questions:
  1. Is there any published mapping from entry name to line number?
  2. How much of the archive does the region actually need?
  3. What does a line's Spoje.txt look like, to compare with the map feed?
"""

import io
import sys
import zipfile

VYSOCINA = {"JI", "TR", "PE", "HB", "ZR"}
WANTED = {"764337", "764931", "764420", "764931"}


def field(text, index):
    parts = text.strip().split('","')
    parts[0] = parts[0].lstrip('"')
    parts[-1] = parts[-1].rstrip('";')
    return parts[index] if index < len(parts) else ""


def main():
    matches = {}
    vysocina_entries = []
    total = 0
    name_matches_line = 0

    with zipfile.ZipFile("JDF.zip") as outer:
        names = outer.namelist()
        print(f"entries: {len(names)}")
        for name in names:
            total += 1
            try:
                with zipfile.ZipFile(io.BytesIO(outer.read(name))) as inner:
                    linky = inner.read("Linky.txt").decode("cp1250")
            except Exception as error:  # noqa: BLE001
                print(f"  !! {name}: {error}")
                continue

            line = field(linky.splitlines()[0], 0)
            if name == f"{line.lstrip('0')}.zip":
                name_matches_line += 1

            if line in WANTED:
                matches[line] = (name, linky.strip()[:150])

            if len(vysocina_entries) < 400:
                try:
                    with zipfile.ZipFile(io.BytesIO(outer.read(name))) as inner:
                        zastavky = inner.read("Zastavky.txt").decode("cp1250")
                except Exception:  # noqa: BLE001
                    zastavky = ""
                regions = {field(row, 4) for row in zastavky.splitlines()}
                if regions & VYSOCINA:
                    vysocina_entries.append((name, line, sorted(regions & VYSOCINA)))

    print(f"scanned: {total}")
    print(f"entry name equals the line number for: {name_matches_line}")
    print(f"entries whose stops include a Vysočina district: {len(vysocina_entries)} (cap 400)")
    for entry, line, regions in vysocina_entries[:12]:
        print(f"  {entry:>10} -> line {line} {regions}")
    print("wanted lines found in the archive:")
    for line, (name, linky) in sorted(matches.items()):
        print(f"  {line}: entry {name}")
        print(f"      {linky}")


if __name__ == "__main__":
    sys.exit(main())

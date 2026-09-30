#!/usr/bin/env python3
"""Size the Vysočina subset of the JDF export."""

import io
import zipfile

VYSOCINA = {"JI", "TR", "PE", "HB", "ZR"}


def field(row, index):
    parts = row.strip().split('","')
    parts[0] = parts[0].lstrip('"')
    parts[-1] = parts[-1].rstrip('";')
    return parts[index] if index < len(parts) else ""


def main():
    entries = 0
    region_entries = 0
    region_lines = set()
    region_calls = 0
    region_bytes = 0

    with zipfile.ZipFile("JDF.zip") as outer:
        for name in outer.namelist():
            entries += 1
            blob = outer.read(name)
            with zipfile.ZipFile(io.BytesIO(blob)) as inner:
                names = inner.namelist()
                if "Zasspoje.txt" not in names:
                    continue
                zastavky = inner.read("Zastavky.txt").decode("cp1250")
                districts = {field(row, 4) for row in zastavky.splitlines()}
                if not districts & VYSOCINA:
                    continue
                region_entries += 1
                region_lines.add(field(inner.read("Linky.txt").decode("cp1250").splitlines()[0], 0))
                calls = inner.read("Zasspoje.txt")
                region_bytes += sum(
                    len(inner.read(part)) for part in ("Zasspoje.txt", "Spoje.txt", "Zastavky.txt", "Linky.txt")
                )
                region_calls += len(calls.decode("cp1250").splitlines())

    print(f"archive entries:            {entries}")
    print(f"entries touching Vysočina:  {region_entries}")
    print(f"distinct lines:             {len(region_lines)}")
    print(f"stop calls:                 {region_calls}")
    print(f"text of the needed files:   {region_bytes / 1e6:.1f} MB")
    print(f"archive download:           106 MB (one file, whole country)")


if __name__ == "__main__":
    main()

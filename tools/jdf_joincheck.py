#!/usr/bin/env python3
"""Check whether the map feed's Spoj and Zastávka really match the JDF timetable.

Takes live vehicles from the map's own feed, reads their info window, then looks
up the same run in the official JDF export.
"""

import io
import json
import re
import urllib.request
import zipfile

BASE = "https://mapavdv.kr-vysocina.cz"
HEADERS = {"X-Requested-With": "XMLHttpRequest", "User-Agent": "vdvmap-investigation"}


def get(url):
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read().decode("utf-8", errors="replace")


def field(text, index):
    parts = text.strip().split('","')
    parts[0] = parts[0].lstrip('"')
    parts[-1] = parts[-1].rstrip('";')
    return parts[index] if index < len(parts) else ""


def line_entry_map():
    """line number -> [(entry name, Linky.txt row)]"""
    mapping = {}
    with zipfile.ZipFile("JDF.zip") as outer:
        for name in outer.namelist():
            with zipfile.ZipFile(io.BytesIO(outer.read(name))) as inner:
                row = inner.read("Linky.txt").decode("cp1250").splitlines()[0]
            mapping.setdefault(field(row, 0), []).append((name, row))
    return mapping


def run_of(entry_name, spoj):
    with zipfile.ZipFile("JDF.zip") as outer:
        with zipfile.ZipFile(io.BytesIO(outer.read(entry_name))) as inner:
            spoje = inner.read("Spoje.txt").decode("cp1250")
            calls = inner.read("Zasspoje.txt").decode("cp1250")
            zastavky = inner.read("Zastavky.txt").decode("cp1250")

    known = {field(row, 1) for row in spoje.splitlines()}
    stops = {}
    for row in zastavky.splitlines():
        stops[field(row, 0)] = (field(row, 1), field(row, 2))

    sequence = []
    for row in calls.splitlines():
        if field(row, 1) != spoj:
            continue
        stop = stops.get(field(row, 3), ("?", "?"))
        name = stop[0] if not stop[1] else f"{stop[0]},{stop[1]}"
        sequence.append((field(row, 2), name, field(row, 10), field(row, 11)))
    return known, sequence


def main():
    points = get(f"{BASE}/Ajax/GetPoints")
    vehicles = re.findall(r'"text":"(\d{6})","traction":"(\w+)","lat":"([\d.\-]+)","lng":"([\d.\-]+)",\s*\}?\s*\}?\s*,\s*"id":(\d+)', points)
    if not vehicles:
        vehicles = re.findall(r'"text":"(\d{6})".{0,400}?"id":(-?\d+)', points, re.S)
        vehicles = [(a, "", "", "", b) for a, b in vehicles]
    print(f"vehicles in the live feed: {len(vehicles)}")

    mapping = line_entry_map()
    print(f"lines in the archive: {len(mapping)}")

    checked = 0
    for entry in vehicles:
        text, _traction, _lat, _lng, vehicle_id = entry
        if text not in mapping:
            continue
        html = get(f"{BASE}/Ajax/OpenInfoWindow?id={vehicle_id}")
        line = re.search(r"Linka</th>\s*<td>(\d+)</td>", html)
        spoj = re.search(r"Spoj</th>\s*<td>(\d+)</td>", html)
        stop = re.search(r"Zast.vka</th>\s*<td>(.*?)</td>", html, re.S)
        if not (line and spoj):
            continue
        line, spoj = line.group(1), spoj.group(1)
        reported = re.sub(r"&#x?[0-9A-Fa-f]+;", "", stop.group(1)).strip() if stop else "?"
        candidates = mapping.get(line, [])
        found = False
        for entry_name, _row in candidates:
            known, sequence = run_of(entry_name, spoj)
            if spoj not in known:
                continue
            names = [name for _i, name, _a, _d in sequence]
            hit = any(reported.split(",")[0].lower() in name.lower() for name in names)
            print(f"  vehicle {vehicle_id}: line {line} spoj {spoj} -> entry {entry_name}: "
                  f"{len(sequence)} calls, zastavka '{reported}' {'FOUND' if hit else 'NOT FOUND'}")
            print(f"      {names[:4]} ...")
            found = True
        if not found:
            print(f"  vehicle {vehicle_id}: line {line} spoj {spoj} -> NO MATCH "
                  f"({len(candidates)} entries for that line)")
        checked += 1
        if checked >= 6:
            break
    print(f"checked {checked} vehicles")


if __name__ == "__main__":
    main()

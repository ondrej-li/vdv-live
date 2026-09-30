#!/usr/bin/env python3
"""List the AJAX endpoints the map site itself uses, and query the catalogue."""

import json
import re
import urllib.parse
import urllib.request

BASE = "https://mapavdv.kr-vysocina.cz"
HEADERS = {"X-Requested-With": "XMLHttpRequest", "User-Agent": "vdvmap-investigation"}


def get(url, headers=None):
    request = urllib.request.Request(url, headers=headers or HEADERS)
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read().decode("utf-8", errors="replace")


def endpoints():
    html = get(f"{BASE}/")
    sources = re.findall(r'<script[^>]+src="([^"]+)"', html)
    found = set()
    for source in sources:
        url = urllib.parse.urljoin(f"{BASE}/", source)
        if not url.startswith("http"):
            continue
        try:
            script = get(url, headers={"User-Agent": "vdvmap-investigation"})
        except Exception as error:  # noqa: BLE001
            print(f"  (could not read {source}: {error})")
            continue
        found |= set(re.findall(r"/Ajax/[A-Za-z]+", script))
        found |= set(re.findall(r'url:\s*"([^"]+)"', script))
    return found


def catalogue():
    query = """
    PREFIX dcat: <http://www.w3.org/ns/dcat#>
    PREFIX dct: <http://purl.org/dc/terms/>
    SELECT ?title (GROUP_CONCAT(DISTINCT ?download; separator=" | ") AS ?files) WHERE {
      ?dataset a dcat:Dataset ; dct:title ?title ; dct:publisher ?publisher .
      OPTIONAL { ?dataset dcat:distribution ?d . ?d dcat:downloadURL ?download . }
      FILTER(CONTAINS(STR(?publisher), "70890749"))
    }
    GROUP BY ?title LIMIT 40
    """
    url = "https://data.gov.cz/sparql?" + urllib.parse.urlencode({"query": query})
    request = urllib.request.Request(
        url, headers={"Accept": "application/sparql-results+json", "User-Agent": "vdvmap-investigation"}
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        data = json.load(response)
    return data["results"]["bindings"]


def main():
    print("=== map AJAX endpoints ===")
    for endpoint in sorted(endpoints()):
        print(" ", endpoint)

    print("=== datasets published by Kraj Vysočina ===")
    for row in catalogue():
        title = row["title"]["value"]
        files = row.get("files", {}).get("value", "").split(" | ")
        interesting = any(
            word in title.lower() for word in ("doprav", "zastáv", "jízd", "linek", "link")
        )
        print(f"  {'*' if interesting else ' '} {title[:88]}")
        if interesting:
            for file in files[:2]:
                if file:
                    print(f"      {file[:110]}")


if __name__ == "__main__":
    main()

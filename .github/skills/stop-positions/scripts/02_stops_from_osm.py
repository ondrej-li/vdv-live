#!/usr/bin/env python3
"""Stage 2: every stop, village and hamlet OpenStreetMap knows inside the rectangle.

The rectangle is the one in `common.REGION_BBOX`, slightly larger than the region so
that a stop just over the border is not lost. Two queries: stop-like elements
(`highway=bus_stop`, `public_transport=platform`/`stop_position`, and platform ways) and
place nodes (city, town, village, hamlet, suburb), which are what the later stages use to
say where a village is.

Usage: 02_stops_from_osm.py
Cached in `build/stops/02_osm.json`; `REFRESH_OSM=1` asks again.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

STOPS_QUERY = """
[out:json][timeout:180];
(
  node["highway"="bus_stop"](%s);
  node["public_transport"="stop_position"]["bus"="yes"](%s);
  node["public_transport"="platform"](%s);
  way["highway"="platform"](%s);
  way["public_transport"="platform"](%s);
);
out center tags;""" % ((common.REGION_BBOX,) * 5)

PLACES_QUERY = """
[out:json][timeout:180];
node["place"~"^(city|town|village|hamlet|suburb)$"](%s);
out center tags;""" % common.REGION_BBOX


def main():
    cached = common.load_stage("02_osm.json")
    if cached.get("stops") and os.environ.get("REFRESH_OSM") != "1":
        print("stage 2: using the cached OpenStreetMap extract (%d stops, %d places)"
              % (len(cached["stops"]), len(cached.get("places", []))), file=sys.stderr)
        return 0

    print("stage 2: asking OpenStreetMap over %s" % common.REGION_BBOX, file=sys.stderr)
    stops = common.ask_overpass(STOPS_QUERY)
    places = common.ask_overpass(PLACES_QUERY)

    # Overpass refuses work under load (504) and a failed query comes back empty, which
    # must not be written over a good cache: a stop pipeline with no village nodes places
    # half as much, silently.
    if not stops:
        raise SystemExit("the stop query came back empty; try again, or REFRESH_OSM=1 once "
                         "Overpass is answering")
    if not places:
        existing = common.load_stage("02_osm.json")
        if existing.get("places"):
            print("stage 2: the place query came back empty; keeping the %d nodes already "
                  "extracted" % len(existing["places"]), file=sys.stderr)
            places = existing["places"]
        else:
            raise SystemExit("the place query came back empty and there is no cache")

    common.save_stage("02_osm.json", {"stops": stops, "places": places})
    print("stage 2: %d stop elements, %d place nodes" % (len(stops), len(places)),
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

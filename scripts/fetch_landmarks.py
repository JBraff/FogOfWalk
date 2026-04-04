#!/usr/bin/env python3
"""
fetch_landmarks.py — Download notable landmarks from Wikidata and save as JSON.

Usage:
    python3 fetch_landmarks.py [--min-sitelinks N] [--output FILE]

Options:
    --min-sitelinks N   Minimum number of Wikipedia language editions required
                        (higher = more famous). Default: 10
    --output FILE       Output JSON path. Default: landmarks.json

The script queries Wikidata for items that have:
  - Coordinates (P625)
  - An English Wikipedia article (notability gate)
  - An "instance of" (P31) matching a curated set of landmark types
  - At least --min-sitelinks Wikipedia editions

Results are written as a JSON array sorted by (lat, lon) for easy inspection.
"""

import argparse
import json
import sys
import time
from collections import Counter
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError
from urllib.parse import urlencode

# ---------------------------------------------------------------------------
# Wikidata instance-of (P31) values we consider "landmarks".
# Each entry is (wikidata_QID, human_label, app_category).
# app_category maps to the existing MKPointOfInterestCategory names so the
# iOS side can reuse its icon/radius tables.
# ---------------------------------------------------------------------------
LANDMARK_TYPES = [
    # Museums & culture
    ("Q33506",   "museum",                 "museum"),
    ("Q207694",  "art museum",             "museum"),
    ("Q1030034", "science museum",         "museum"),
    ("Q1565839", "natural history museum", "museum"),

    # Performing arts
    ("Q24354",   "theater building",       "theater"),
    ("Q1060829", "concert hall",           "theater"),
    ("Q153562",  "opera house",            "theater"),

    # Libraries
    ("Q7075",    "library",                "library"),

    # Parks & nature
    ("Q46169",   "national park",          "nationalPark"),
    ("Q179049",  "national monument",      "landmark"),
    ("Q3914",    "nature reserve",         "nationalPark"),

    # Stadiums & arenas
    ("Q483110",  "stadium",                "stadium"),
    ("Q1137812", "multi-purpose stadium",  "stadium"),
    ("Q2044656", "arena",                  "stadium"),

    # Amusement / theme parks
    ("Q194195",  "amusement park",         "amusementPark"),

    # Zoos & aquariums
    ("Q43501",   "zoo",                    "zoo"),
    ("Q45782",   "aquarium",               "zoo"),
    ("Q174782",  "botanical garden",       "zoo"),

    # Universities & campuses
    ("Q3918",    "university",             "university"),
    ("Q189004",  "college",               "university"),

    # Airports
    ("Q1248784", "airport",               "airport"),

    # Generic notable landmarks
    ("Q570116",  "tourist attraction",    "landmark"),
    ("Q839954",  "archaeological site",   "landmark"),
    ("Q23413",   "castle",               "landmark"),
    ("Q44613",   "monastery",            "landmark"),
    ("Q16560",   "palace",               "landmark"),
    ("Q12518",   "tower",               "landmark"),
    ("Q12280",   "bridge",              "landmark"),
    ("Q4989906", "monument",            "landmark"),
    ("Q1076486", "sports venue",        "stadium"),
]

# De-duplicate by QID
_seen_qids: set[str] = set()
UNIQUE_TYPES: list[tuple[str, str, str]] = []
for _qid, _label, _cat in LANDMARK_TYPES:
    if _qid not in _seen_qids:
        _seen_qids.add(_qid)
        UNIQUE_TYPES.append((_qid, _label, _cat))

QID_TO_CATEGORY = {qid: cat for qid, _, cat in UNIQUE_TYPES}

SPARQL_ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = "FogOfWalk-LandmarkFetcher/1.0 (fog-of-walk iOS app; educational)"
BATCH_SIZE = 10  # QIDs per query — keeps each query well under the 60s timeout


def sparql_query(sparql: str, retries: int = 3) -> dict:
    """Execute a SPARQL query and return parsed JSON."""
    params = urlencode({"query": sparql, "format": "json"})
    url = f"{SPARQL_ENDPOINT}?{params}"
    req = Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "application/sparql-results+json",
    })
    for attempt in range(retries):
        try:
            with urlopen(req, timeout=55) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except HTTPError as e:
            if e.code == 429:
                wait = 15 * (attempt + 1)
                print(f"  Rate-limited, waiting {wait}s...", flush=True)
                time.sleep(wait)
            elif attempt < retries - 1:
                print(f"  HTTP {e.code}, retrying in 5s...", flush=True)
                time.sleep(5)
            else:
                raise
        except URLError:
            if attempt < retries - 1:
                time.sleep(5)
            else:
                raise
    raise RuntimeError("Max retries exceeded")


def build_query(qids: list[str], min_sitelinks: int) -> str:
    qid_values = " ".join(f"wd:{q}" for q in qids)
    return f"""
SELECT DISTINCT ?item ?itemLabel ?itemDescription ?coord ?image ?instanceOf WHERE {{
  VALUES ?instanceOf {{ {qid_values} }}
  ?item wdt:P31 ?instanceOf .
  ?item wdt:P625 ?coord .
  ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> .
  ?item wikibase:sitelinks ?sitelinks .
  FILTER(?sitelinks >= {min_sitelinks})
  OPTIONAL {{ ?item wdt:P18 ?image . }}
  SERVICE wikibase:label {{
    bd:serviceParam wikibase:language "en" .
  }}
}}
"""


def parse_coord(coord_str: str) -> tuple[float, float] | None:
    """Parse 'Point(LON LAT)' → (lat, lon)."""
    try:
        inner = coord_str.removeprefix("Point(").removesuffix(")")
        lon_s, lat_s = inner.split()
        return round(float(lat_s), 6), round(float(lon_s), 6)
    except Exception:
        return None


def fetch_batch(qids: list[str], min_sitelinks: int) -> list[dict]:
    query = build_query(qids, min_sitelinks)
    data = sparql_query(query)
    results = []
    for row in data.get("results", {}).get("bindings", []):
        coord_str = row.get("coord", {}).get("value", "")
        latlon = parse_coord(coord_str)
        if not latlon:
            continue
        lat, lon = latlon

        instance_qid = row["instanceOf"]["value"].rsplit("/", 1)[-1]
        category = QID_TO_CATEGORY.get(instance_qid, "landmark")

        item_qid = row["item"]["value"].rsplit("/", 1)[-1]
        results.append({
            "id":          item_qid,
            "name":        row.get("itemLabel", {}).get("value", ""),
            "description": row.get("itemDescription", {}).get("value", "") or None,
            "lat":         lat,
            "lon":         lon,
            "category":    category,
            "image":       row.get("image", {}).get("value", "") or None,
        })
    return results


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--min-sitelinks", type=int, default=10,
                        help="Minimum Wikipedia language editions (default: 10)")
    parser.add_argument("--output", default="landmarks.json",
                        help="Output JSON file (default: landmarks.json)")
    args = parser.parse_args()

    all_qids = [qid for qid, _, _ in UNIQUE_TYPES]
    batches = [all_qids[i:i + BATCH_SIZE] for i in range(0, len(all_qids), BATCH_SIZE)]

    print(f"Fetching landmarks from Wikidata (min_sitelinks={args.min_sitelinks})...")
    print(f"  {len(all_qids)} landmark types → {len(batches)} batches of up to {BATCH_SIZE}")

    landmarks: dict[str, dict] = {}  # QID → record (dedup across batches)
    errors = 0

    for i, batch in enumerate(batches, 1):
        labels = [label for qid, label, _ in UNIQUE_TYPES if qid in batch]
        print(f"  Batch {i}/{len(batches)}: {', '.join(labels)}", flush=True)
        try:
            items = fetch_batch(batch, args.min_sitelinks)
            for item in items:
                # If seen before, prefer the most specific (non-generic) category
                existing = landmarks.get(item["id"])
                if existing is None or (existing["category"] == "landmark" and item["category"] != "landmark"):
                    landmarks[item["id"]] = item
            print(f"    → {len(items)} results ({len(landmarks)} total unique)", flush=True)
        except Exception as e:
            print(f"    ERROR: {e}", file=sys.stderr)
            errors += 1

        if i < len(batches):
            time.sleep(1)

    # Sort by (lat, lon) for reproducible diffs and easy geo inspection
    sorted_landmarks = sorted(landmarks.values(), key=lambda x: (x["lat"], x["lon"]))

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(sorted_landmarks, f, ensure_ascii=False, indent=2)

    print(f"\nDone. {len(sorted_landmarks)} landmarks written to {args.output}")
    if errors:
        print(f"  ({errors} batch(es) failed — rerun to retry)", file=sys.stderr)

    cats = Counter(lm["category"] for lm in sorted_landmarks)
    print("\nCategory breakdown:")
    for cat, count in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"  {cat:<20} {count:>6}")

    # Show a few sample records
    print("\nSample records:")
    for lm in sorted_landmarks[:3]:
        print(f"  {lm['name']!r} ({lm['category']}) @ {lm['lat']}, {lm['lon']}")
        if lm["description"]:
            print(f"    {lm['description'][:80]}")
        if lm["image"]:
            print(f"    image: {lm['image'][:60]}...")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
make_landmarks_db.py — Convert landmarks JSON to a SQLite database with an R-tree index.

Usage:
    python3 make_landmarks_db.py [--input FILE] [--output FILE]

Options:
    --input FILE    Input JSON (default: landmarks.json)
    --output FILE   Output SQLite path (default: landmarks.sqlite)

The generated database has two tables:
  landmarks       — one row per landmark (id, name, description, lat, lon, category, image)
  landmarks_rtree — R-tree spatial index for fast bounding-box queries

This file should be bundled with the iOS app as a read-only resource.
"""

import argparse
import json
import os
import sqlite3

SCHEMA = """
CREATE TABLE landmarks (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    lat         REAL NOT NULL,
    lon         REAL NOT NULL,
    category    TEXT NOT NULL,
    image       TEXT
);

-- R-tree index: each point is stored as a degenerate rectangle (min==max).
-- iOS ships SQLite with R-tree support compiled in.
CREATE VIRTUAL TABLE landmarks_rtree USING rtree(
    rowid,
    min_lat, max_lat,
    min_lon, max_lon
);
"""


def build(input_path: str, output_path: str) -> None:
    with open(input_path, encoding="utf-8") as f:
        landmarks = json.load(f)

    # Deduplicate by id, keeping first occurrence.
    seen_ids: set[str] = set()
    unique: list[dict] = []
    for lm in landmarks:
        if lm["id"] not in seen_ids:
            seen_ids.add(lm["id"])
            unique.append(lm)
    duplicates = len(landmarks) - len(unique)
    if duplicates:
        print(f"  Skipped {duplicates} duplicate id(s)")
    landmarks = unique

    if os.path.exists(output_path):
        os.remove(output_path)

    conn = sqlite3.connect(output_path)
    conn.executescript(SCHEMA)

    insert_landmark = """
        INSERT INTO landmarks (id, name, description, lat, lon, category, image)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """
    insert_rtree = """
        INSERT INTO landmarks_rtree (rowid, min_lat, max_lat, min_lon, max_lon)
        VALUES (?, ?, ?, ?, ?)
    """

    cur = conn.cursor()
    for lm in landmarks:
        cur.execute(insert_landmark, (
            lm["id"],
            lm["name"],
            lm.get("description"),
            lm["lat"],
            lm["lon"],
            lm["category"],
            lm.get("image"),
        ))
        rowid = cur.lastrowid
        cur.execute(insert_rtree, (rowid, lm["lat"], lm["lat"], lm["lon"], lm["lon"]))

    conn.commit()

    # Quick sanity check
    count = conn.execute("SELECT COUNT(*) FROM landmarks").fetchone()[0]
    rtree_count = conn.execute("SELECT COUNT(*) FROM landmarks_rtree").fetchone()[0]
    conn.close()

    size_kb = os.path.getsize(output_path) / 1024
    print(f"Wrote {output_path}")
    print(f"  {count:,} landmarks, {rtree_count:,} rtree entries")
    print(f"  File size: {size_kb:.0f} KB ({size_kb/1024:.1f} MB)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--input",  default="landmarks.json",   help="Input JSON file")
    parser.add_argument("--output", default="landmarks.sqlite", help="Output SQLite file")
    args = parser.parse_args()
    build(args.input, args.output)


if __name__ == "__main__":
    main()

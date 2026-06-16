#!/usr/bin/env python3
"""
Add fame signals (vote_count + popularity) to a catalog.

Two modes (chosen by --catalog):

  arabictoons : LIGHT pass. Items already have a matched `tmdb` block with a
                `tmdb_id`; fetch /{type}/{id} once and fill in vote_count +
                popularity. No re-matching, no image refetch.

  stardima    : FULL pass. Items have NO tmdb at all; match each title+year to
                TMDB (reusing enrich_tmdb's Arabic cleaning/alias/search) and
                build a full tmdb block (which now includes vote_count +
                popularity via enrich_tmdb.build_tmdb_block).

Resumable: saves every 25 items; rerun to continue. Reuses the TMDB key
resolution from enrich_tmdb (tmdb_key.txt / TMDB_TOKEN / TMDB_API_KEY / --key).

Usage:
  python enrich_extra.py --catalog arabictoons --input ../../assets/arabictoons_catalog.json
  python enrich_extra.py --catalog stardima    --input ../../assets/stardima_catalog.json
"""

import os
import sys
import json
import time
import argparse

import enrich_tmdb as E  # reuse session/key/search/build helpers

PATH = None


def save(cat, path):
    # Write a full backup copy first (atomic), then overwrite the real file's
    # CONTENTS in place. os.replace() can't be used here: on Windows the Dart
    # analysis server keeps a shared-read handle on the bundled asset, which
    # blocks rename/delete of the target but still permits an in-place write.
    data = json.dumps(cat, ensure_ascii=False, indent=2).encode("utf-8")
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    for _ in range(8):
        try:
            with open(path, "r+b") as f:
                f.truncate(0)
                f.write(data)
            os.remove(tmp)
            return
        except PermissionError:
            time.sleep(0.5)


def light_arabictoons(session, cat):
    """Fill vote_count + popularity on already-matched items."""
    items = [("tv", s) for s in cat.get("shows", [])] + \
            [("movie", m) for m in cat.get("movies", [])]
    todo = [(k, it) for k, it in items
            if isinstance(it.get("tmdb"), dict)
            and it["tmdb"].get("tmdb_id")
            and "vote_count" not in it["tmdb"]]
    print(f"arabictoons: {len(items)} items, {len(todo)} need vote_count.")
    done = 0
    for kind, it in todo:
        t = it["tmdb"]
        d = E.api_get(session, f"/{t.get('type', kind)}/{t['tmdb_id']}",
                      language="en") or {}
        t["vote_count"] = d.get("vote_count")
        t["popularity"] = d.get("popularity")
        time.sleep(E.SLEEP)
        done += 1
        if done % 25 == 0:
            save(cat, PATH)
            print(f"  [{done}/{len(todo)}]")
    return done


def full_stardima(session, cat):
    """Build tmdb blocks (with vote_count/popularity) for unmatched items."""
    items = [("movie", m) for m in cat.get("movies", [])] + \
            [("tv", s) for s in cat.get("tvshows", [])]
    todo = [(k, it) for k, it in items if not it.get("tmdb")]
    print(f"stardima: {len(items)} items, {len(todo)} to match.")
    matched = done = 0
    for kind, it in todo:
        res, conf, q = E.search_best(session, it, kind)
        if res and conf >= E.MIN_CONFIDENCE and res.get("poster_path"):
            it["tmdb"] = E.build_tmdb_block(session, res, kind, conf, q)
            matched += 1
        else:
            it["tmdb"] = None
        done += 1
        if done % 25 == 0:
            save(cat, PATH)
            print(f"  [{done}/{len(todo)}] matched={matched}")
    return matched


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", required=True, choices=["arabictoons", "stardima"])
    p.add_argument("--input", required=True)
    p.add_argument("--key", default=None)
    args, _ = p.parse_known_args()

    key = E.get_key()
    if not key:
        print("No TMDB key found (tmdb_key.txt / TMDB_TOKEN / TMDB_API_KEY / --key).")
        sys.exit(1)
    session = E.make_session(key)
    if not E.api_get(session, "/configuration"):
        print("Could not reach TMDB / key invalid.")
        sys.exit(1)
    print("TMDB key OK.")

    global PATH
    PATH = args.input
    cat = json.load(open(PATH, encoding="utf-8"))

    if args.catalog == "arabictoons":
        n = light_arabictoons(session, cat)
        save(cat, PATH)
        print(f"Done. filled vote_count on {n} items -> {PATH}")
    else:
        n = full_stardima(session, cat)
        save(cat, PATH)
        print(f"Done. matched {n} Stardima items -> {PATH}")


if __name__ == "__main__":
    main()

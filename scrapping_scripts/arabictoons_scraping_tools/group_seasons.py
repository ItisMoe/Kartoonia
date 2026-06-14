#!/usr/bin/env python3
"""
Group per-season show entries into one series each.

The scraper produces one entry per season/part, e.g.:
    سبونج بوب الموسم 11, سبونج بوب الموسم 10, ... سبونج بوب
    كابتن ماجد الجزء 5, ... كابتن ماجد الحزء 1
This script merges them into a single series with a seasons[] array:

    {
      "title": "سبونج بوب",
      "type": "show",
      "season_count": 11,
      "total_episodes": 263,
      "slug": "...", "thumbnail_url": "...", "rating": 3.5,
      "ids": ["...","..."],
      "seasons": [
        { "season_number": 1, "season_title": "سبونج بوب",
          "id": "...", "slug": "...", "thumbnail_url": "...",
          "rating": ..., "page_url": "...", "total_episodes": 20,
          "episodes": [ ... unchanged ... ] },
        ...
      ]
    }

It only strips EXPLICIT season markers (الموسم / الجزء / الحزء + number or
Arabic ordinal) at the end of a title, then groups by the remaining base name.
That is conservative: different series that merely share a prefix (e.g.
"بن 10", "بن 10 اومنيفرس", "بن 10 الين فورس") stay separate.

Input : arabic_toons_catalog.json   (the flat scraped catalog)
Output: arabic_toons_grouped.json   (original file is left untouched)

Movies are copied through unchanged.
"""

import os
import re
import json
import unicodedata
from datetime import datetime, timezone
from collections import Counter

SOURCE = "arabic_toons_catalog.json"
OUTPUT = "arabic_toons_grouped.json"

# Arabic ordinals -> integer (worded season numbers)
AR_ORD = {
    "الأول": 1, "الاول": 1, "الثاني": 2, "الثانى": 2, "الثالث": 3,
    "الرابع": 4, "الخامس": 5, "السادس": 6, "السابع": 7, "الثامن": 8,
    "التاسع": 9, "العاشر": 10, "الحادي عشر": 11, "الحادى عشر": 11,
    "الثاني عشر": 12, "الثانى عشر": 12, "الثالث عشر": 13, "الرابع عشر": 14,
    "الخامس عشر": 15, "السادس عشر": 16, "السابع عشر": 17, "الثامن عشر": 18,
}
MARKER = r"(?:الموسم|الجزء|الحزء)"


def parse_title(title):
    """Return (base_title, season_number_or_None)."""
    t = re.sub(r"\s+", " ", (title or "")).strip()
    # marker + digits at the end
    m = re.search(r"\s*" + MARKER + r"\s+(\d+)\s*$", t)
    if m:
        return t[:m.start()].strip(), int(m.group(1))
    # marker + Arabic ordinal phrase at the end
    m = re.search(r"\s*" + MARKER + r"\s+(.+)$", t)
    if m:
        ordtxt = m.group(1).strip()
        if ordtxt in AR_ORD:
            return t[:m.start()].strip(), AR_ORD[ordtxt]
    return t, None


def norm_key(s):
    """Normalisation used only for the grouping key (not for display)."""
    s = unicodedata.normalize("NFKC", s or "")
    s = (s.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
           .replace("ى", "ي"))
    s = re.sub(r"ـ", "", s)               # tatweel
    s = re.sub(r"\s+", " ", s).strip()
    return s


def group_catalog(cat):
    """Return (grouped_dict, stats_dict)."""
    shows = cat.get("shows", [])
    movies = cat.get("movies", [])

    groups = {}   # key -> list of (season_number, base_text, show)
    for sh in shows:
        base, num = parse_title(sh.get("title", ""))
        key = norm_key(base)
        groups.setdefault(key, []).append((num, base, sh))

    grouped_shows = []
    for key, members in groups.items():
        # display title: most common base spelling, tie-break shortest
        base_counts = Counter(b for _, b, _ in members)
        display = sorted(base_counts.items(),
                         key=lambda kv: (-kv[1], len(kv[0])))[0][0]

        seasons = []
        for num, base, sh in members:
            seasons.append({
                "season_number": num,
                "season_title": sh.get("title", ""),
                "id": sh.get("id"),
                "slug": sh.get("slug"),
                "thumbnail_url": sh.get("thumbnail_url"),
                "rating": sh.get("rating"),
                "page_url": sh.get("page_url"),
                "total_episodes": sh.get("total_episodes",
                                         len(sh.get("episodes", []))),
                "episodes": sh.get("episodes", []),
            })
        # sort: numbered seasons ascending, unnumbered first
        seasons.sort(key=lambda s: (s["season_number"] is not None,
                                    s["season_number"] or 0))

        # representative season = the one with the most episodes
        rep = max(seasons, key=lambda s: s["total_episodes"])
        total_eps = sum(s["total_episodes"] for s in seasons)

        grouped_shows.append({
            "title": display,
            "type": "show",
            "season_count": len(seasons),
            "total_episodes": total_eps,
            "ids": [s["id"] for s in seasons],
            "slug": rep["slug"],
            "thumbnail_url": rep["thumbnail_url"],
            "rating": rep["rating"],
            "seasons": seasons,
        })

    # sort series by title for stability
    grouped_shows.sort(key=lambda g: norm_key(g["title"]))

    grouped = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": SOURCE,
        "total_series": len(grouped_shows),
        "total_show_entries_before": len(shows),
        "total_movies": len(movies),
        "shows": grouped_shows,
        "movies": movies,
    }
    multi = [g for g in grouped_shows if g["season_count"] > 1]
    stats = {
        "series": len(grouped_shows),
        "before": len(shows),
        "multi_season": len(multi),
        "movies": len(movies),
        "top": sorted(multi, key=lambda g: -g["season_count"])[:15],
    }
    return grouped, stats


def run(source=SOURCE, output=OUTPUT, log=print):
    cat = json.load(open(source, encoding="utf-8"))
    grouped, stats = group_catalog(cat)
    tmp = output + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(grouped, f, ensure_ascii=False, indent=2)
    os.replace(tmp, output)
    log(f"{stats['before']} show entries -> {stats['series']} series "
        f"({stats['multi_season']} have multiple seasons). "
        f"Movies: {stats['movies']}.")
    log(f"written: {output}")
    for g in stats["top"]:
        log(f"   {g['season_count']:>2} seasons  |  {g['title']}")
    return stats


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    run()

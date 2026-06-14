#!/usr/bin/env python3
"""Writes a human-readable STATUS.txt every few seconds describing where the
arabic-toons scrape is: current show, progress out of the chosen classics, and
out of the whole catalog. Safe to run alongside the scraper (read-only)."""
import json, re, os, time
from datetime import datetime

LOG = "scraper_errors.log"
PROGRESS = "progress.json"
PRIORITY = "priority_shows.json"
STATUS = "STATUS.txt"
ALL_SHOWS = 1150          # full catalog size
ALL_MOVIES = 291

def tail(path, n=400):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.readlines()[-n:]
    except OSError:
        return []

def last_match(lines, pattern):
    out = None
    for ln in lines:
        m = re.search(pattern, ln)
        if m:
            out = m
    return out

def last_index(lines, pattern):
    idx = -1
    for i, ln in enumerate(lines):
        if re.search(pattern, ln):
            idx = i
    return idx

def python_running():
    try:
        return "python.exe" in os.popen("tasklist").read()
    except Exception:
        return None

def build():
    try:
        prog = json.load(open(PROGRESS, encoding="utf-8"))
        shows_done = len(prog.get("shows", []))
        movies_done = len(prog.get("movies", []))
    except Exception:
        shows_done = movies_done = 0
    try:
        chosen = len(json.load(open(PRIORITY, encoding="utf-8")))
    except Exception:
        chosen = 0

    lines = tail(LOG)
    cur_show = last_match(lines, r"\[show (\d+)/(\d+)\]\s*(.+?)\s*\((\d+)\)")
    cur_movie = last_match(lines, r"\[movie (\d+)/(\d+)\]\s*(.+?)\s*\((\d+)\)")
    cur_eps = last_match(lines, r"show '(.+?)' -> (\d+) episodes")

    running = python_running()
    # Phase is whichever section appears most recently in the log (the log
    # accumulates across runs, so an old test-run movie line can linger).
    show_i = last_index(lines, r"\[show \d+/\d+\]")
    movie_i = last_index(lines, r"\[movie \d+/\d+\]")
    in_movies = movie_i > show_i
    phase = "MOVIES" if in_movies else "SHOWS"

    L = []
    L.append("ARABIC-TOONS SCRAPE — LIVE STATUS")
    L.append("updated: " + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    L.append("process: " + ("RUNNING" if running else "NOT running (finished or stopped)"))
    L.append("phase:   " + phase)
    L.append("")
    if not in_movies and cur_show:
        idx, total, title, sid = cur_show.groups()
        L.append(f"CURRENT SHOW:  {title}")
        L.append(f"  position in chosen classics : {idx} of {total}")
        if cur_eps and cur_eps.group(1) in title:
            L.append(f"  episodes in this show       : {cur_eps.group(2)}")
    if in_movies and cur_movie:
        idx, total, title, mid = cur_movie.groups()
        L.append(f"CURRENT MOVIE: {title}")
        L.append(f"  position in movies          : {idx} of {total}")
    L.append("")
    L.append("--- TOTALS SAVED SO FAR ---")
    L.append(f"shows done : {shows_done}")
    L.append(f"  out of chosen classics : {shows_done} / {chosen}")
    L.append(f"  out of whole catalog   : {shows_done} / {ALL_SHOWS}")
    L.append(f"movies done: {movies_done} / {ALL_MOVIES}")
    pct = (shows_done / chosen * 100) if chosen else 0
    L.append("")
    L.append(f"chosen-shows progress: {pct:5.1f}%")
    bar = int(pct / 5)
    L.append("[" + "#" * bar + "-" * (20 - bar) + "]")
    return "\n".join(L) + "\n"

def main():
    while True:
        try:
            tmp = STATUS + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(build())
            os.replace(tmp, STATUS)
        except Exception as e:
            try:
                open(STATUS, "w", encoding="utf-8").write("status error: %s\n" % e)
            except Exception:
                pass
        time.sleep(15)

if __name__ == "__main__":
    main()

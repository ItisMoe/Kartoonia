#!/usr/bin/env python3
"""
Simple desktop GUI to continue scraping arabic-toons.com into the existing
catalog (arabic_toons_catalog.json).

What it does
------------
* Resumes from progress.json (the checkpoint) - never re-scrapes a show that's
  already done.
* Scrapes the remaining shows in the full catalog and APPENDS them to the same
  catalog + checkpoint files (atomic, crash-safe writes).
* Shows live progress: current show, episode-within-show, totals, a progress
  bar and a scrolling log.
* Start/Resume and Stop at any time. Stop takes effect within a second or two
  (between episodes); the show in progress is simply re-done next time, so no
  data is corrupted.

It reuses all the scraping logic from scrape_arabic_toons.py - this file is only
the GUI + a thread that can be stopped.

Run:  python gui_scraper.py
"""

import os
import sys
import json
import time
import queue
import threading

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox

# Reuse the existing scraper's functions
import scrape_arabic_toons as scr
from bs4 import BeautifulSoup

ALL_SHOWS_FILE = "all_shows_list.json"     # cached list of every show (id,slug,title)
PRIORITY_FILE = "priority_shows.json"


# --------------------------------------------------------------------------- #
# Show-metadata source
# --------------------------------------------------------------------------- #
def load_all_show_meta():
    """Build the full list of show metadata. Prefer the cached all_shows_list
    (instant); fall back to scraping the catalog live."""
    if os.path.exists(ALL_SHOWS_FILE):
        data = json.load(open(ALL_SHOWS_FILE, encoding="utf-8"))
        out = []
        for row in data:
            iid, slug, title = row[0], row[1], row[2]
            out.append({
                "id": str(iid),
                "slug": slug,
                "title": title,
                "type": "show",
                "thumbnail_url": f"{scr.BASE_URL}/images/anime/cat_{iid}.jpg",
                "page_url": f"{scr.BASE_URL}/{slug}-{iid}-anime-streaming.html",
            })
        return out, "cache"
    # fallback: live catalog scan
    session = scr.get_session()
    return scr.scrape_catalog(session, "cartoon.php", "show"), "live"


# --------------------------------------------------------------------------- #
# GUI
# --------------------------------------------------------------------------- #
class App:
    def __init__(self, root):
        self.root = root
        root.title("Arabic-Toons Scraper")
        root.geometry("760x560")
        root.minsize(640, 460)

        self.q = queue.Queue()
        self.stop_event = threading.Event()
        self.worker = None

        self.classic_only = tk.BooleanVar(value=False)
        self.delay_var = tk.StringVar(value="0.7")

        self._build_ui()
        self._refresh_static_counts()
        self.root.after(150, self._poll)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    # ----- layout -----
    def _build_ui(self):
        pad = {"padx": 10, "pady": 4}

        top = ttk.Frame(self.root)
        top.pack(fill="x", **pad)

        self.state_var = tk.StringVar(value="Idle")
        ttk.Label(top, text="Status:").grid(row=0, column=0, sticky="w")
        self.state_lbl = ttk.Label(top, textvariable=self.state_var,
                                   font=("Segoe UI", 11, "bold"))
        self.state_lbl.grid(row=0, column=1, sticky="w", padx=(4, 0))

        self.counts_var = tk.StringVar(value="")
        ttk.Label(top, textvariable=self.counts_var).grid(
            row=1, column=0, columnspan=4, sticky="w", pady=(2, 0))

        self.remaining_var = tk.StringVar(value="")
        ttk.Label(top, textvariable=self.remaining_var).grid(
            row=2, column=0, columnspan=4, sticky="w")

        # current show / episode
        cur = ttk.LabelFrame(self.root, text="Now scraping")
        cur.pack(fill="x", **pad)
        self.current_var = tk.StringVar(value="-")
        ttk.Label(cur, textvariable=self.current_var,
                  font=("Segoe UI", 10, "bold")).pack(anchor="w", padx=8, pady=(6, 0))
        self.ep_var = tk.StringVar(value="")
        ttk.Label(cur, textvariable=self.ep_var).pack(anchor="w", padx=8)

        self.pbar = ttk.Progressbar(cur, mode="determinate")
        self.pbar.pack(fill="x", padx=8, pady=(4, 4))
        self.pct_var = tk.StringVar(value="")
        ttk.Label(cur, textvariable=self.pct_var).pack(anchor="w", padx=8, pady=(0, 6))

        # options + buttons
        opts = ttk.Frame(self.root)
        opts.pack(fill="x", **pad)
        ttk.Checkbutton(opts, text="Classic/priority shows only",
                        variable=self.classic_only).pack(side="left")
        ttk.Label(opts, text="   Delay (s):").pack(side="left")
        ttk.Entry(opts, textvariable=self.delay_var, width=5).pack(side="left")

        btns = ttk.Frame(self.root)
        btns.pack(fill="x", **pad)
        self.start_btn = ttk.Button(btns, text="▶  Start / Resume",
                                    command=self._start)
        self.start_btn.pack(side="left")
        self.stop_btn = ttk.Button(btns, text="■  Stop", command=self._stop,
                                   state="disabled")
        self.stop_btn.pack(side="left", padx=(8, 0))
        ttk.Button(btns, text="Open folder",
                   command=self._open_folder).pack(side="right")

        # log
        logf = ttk.LabelFrame(self.root, text="Log")
        logf.pack(fill="both", expand=True, **pad)
        self.log = scrolledtext.ScrolledText(logf, height=12, wrap="word",
                                             state="disabled",
                                             font=("Consolas", 9))
        self.log.pack(fill="both", expand=True, padx=4, pady=4)

    # ----- helpers -----
    def _log(self, msg):
        self.log.configure(state="normal")
        self.log.insert("end", time.strftime("%H:%M:%S ") + msg + "\n")
        # keep last ~400 lines
        if int(self.log.index("end-1c").split(".")[0]) > 400:
            self.log.delete("1.0", "100.0")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _refresh_static_counts(self):
        """Read checkpoint + full list to show how many are done / remaining."""
        try:
            cp = scr.load_checkpoint()
            done_shows = len(cp["shows"])
            done_movies = len(cp["movies"])
            scraped_ids = set(cp["scraped_show_ids"])
        except Exception:
            done_shows = done_movies = 0
            scraped_ids = set()
        try:
            meta, _ = load_all_show_meta()
            total = len(meta)
            remaining = len([m for m in meta if m["id"] not in scraped_ids])
        except Exception:
            total = remaining = 0
        self.counts_var.set(
            f"Catalog so far:  {done_shows} shows,  {done_movies} movies")
        self.remaining_var.set(
            f"Shows in full catalog: {total}   |   already done: {len(scraped_ids)}"
            f"   |   remaining: {remaining}")

    def _open_folder(self):
        try:
            os.startfile(os.getcwd())
        except Exception as e:
            messagebox.showinfo("Folder", os.getcwd())

    # ----- start / stop -----
    def _start(self):
        if self.worker and self.worker.is_alive():
            return
        try:
            self.delay = max(0.0, float(self.delay_var.get()))
        except ValueError:
            self.delay = 0.7
            self.delay_var.set("0.7")
        self.stop_event.clear()
        self.start_btn.configure(state="disabled")
        self.stop_btn.configure(state="normal")
        self.state_var.set("Running")
        self._log("=== started ===")
        self.worker = threading.Thread(target=self._run, daemon=True)
        self.worker.start()

    def _stop(self):
        if self.worker and self.worker.is_alive():
            self.stop_event.set()
            self.state_var.set("Stopping… (finishing current episode)")
            self.stop_btn.configure(state="disabled")
            self._log("stop requested")

    def _on_close(self):
        if self.worker and self.worker.is_alive():
            if not messagebox.askokcancel(
                    "Quit", "Scraping is running. Stop and quit?"):
                return
            self.stop_event.set()
            self._log("stopping before exit…")
            self.root.after(500, self._on_close)
            return
        self.root.destroy()

    # ----- worker thread -----
    def _run(self):
        try:
            session = scr.get_session()
            cp = scr.load_checkpoint()
            scraped = set(cp["scraped_show_ids"])
            shows = cp["shows"]
            movies = cp["movies"]

            self.q.put(("log", "loading show list…"))
            meta, src = load_all_show_meta()
            self.q.put(("log", f"show list loaded ({len(meta)} shows, {src})"))

            if self.classic_only.get() and os.path.exists(PRIORITY_FILE):
                pri = {str(x["id"]) for x in json.load(
                    open(PRIORITY_FILE, encoding="utf-8"))}
                meta = [m for m in meta if m["id"] in pri]
                self.q.put(("log", f"classic-only filter: {len(meta)} shows"))

            todo = [m for m in meta if m["id"] not in scraped]
            self.q.put(("total", len(todo)))
            self.q.put(("log", f"{len(todo)} shows to scrape this session"))

            for i, m in enumerate(todo, 1):
                if self.stop_event.is_set():
                    break
                self.q.put(("show", m["title"], i, len(todo)))
                data = self._scrape_one_show(session, m)
                if self.stop_event.is_set() and data is None:
                    break
                if data:
                    shows.append(data)
                    scraped.add(m["id"])
                    cp["scraped_show_ids"] = list(scraped)
                    cp["shows"] = shows
                    scr.save_checkpoint(cp)
                    scr.write_output(shows, movies)
                    self.q.put(("done_one", len(shows), len(movies),
                                data["title"], data["total_episodes"], i))
                else:
                    self.q.put(("log", f"skipped (no page): {m['title']}"))
                time.sleep(self.delay)

            self.q.put(("finished", self.stop_event.is_set(),
                        len(shows), len(movies)))
        except Exception as e:
            self.q.put(("error", str(e)))

    def _scrape_one_show(self, session, meta):
        """Scrape a show + its episodes, checking the stop flag between episodes.
        Returns the show dict, or None if it should be skipped / was stopped."""
        html = scr.fetch(session, meta["page_url"])
        if not html:
            return None
        soup = BeautifulSoup(html, "lxml")
        description = scr.extract_description(soup)
        rating = scr.extract_rating(html)
        episodes = scr.parse_episodes(soup, meta["title"])
        for j, ep in enumerate(episodes, 1):
            if self.stop_event.is_set():
                return None
            self.q.put(("ep", j, len(episodes)))
            eh = scr.fetch(session, ep["episode_url"])
            if eh:
                ep["servers"] = scr.extract_video_servers(eh)
            time.sleep(self.delay)
        return {
            "id": meta["id"],
            "slug": meta["slug"],
            "title": meta["title"],
            "type": "show",
            "thumbnail_url": meta["thumbnail_url"],
            "description": description,
            "rating": rating,
            "total_episodes": len(episodes),
            "page_url": meta["page_url"],
            "episodes": episodes,
        }

    # ----- queue pump (main thread) -----
    def _poll(self):
        try:
            while True:
                msg = self.q.get_nowait()
                kind = msg[0]
                if kind == "log":
                    self._log(msg[1])
                elif kind == "total":
                    self.pbar.configure(maximum=max(1, msg[1]), value=0)
                    self._session_total = msg[1]
                elif kind == "show":
                    title, i, total = msg[1], msg[2], msg[3]
                    self.current_var.set(f"{title}   ({i} / {total})")
                    self.ep_var.set("")
                    self.pbar.configure(value=i - 1)
                    self.pct_var.set(f"{i-1} of {total} done this session")
                elif kind == "ep":
                    j, n = msg[1], msg[2]
                    self.ep_var.set(f"episode {j} / {n}")
                elif kind == "done_one":
                    nshows, nmovies, title, neps, i = msg[1:6]
                    self.counts_var.set(
                        f"Catalog so far:  {nshows} shows,  {nmovies} movies")
                    self.pbar.configure(value=i)
                    self._log(f"✓ {title}  ({neps} episodes)")
                elif kind == "finished":
                    stopped, nshows, nmovies = msg[1], msg[2], msg[3]
                    self.state_var.set("Stopped" if stopped else "Finished ✓")
                    self.current_var.set("-")
                    self.ep_var.set("")
                    self.start_btn.configure(state="normal")
                    self.stop_btn.configure(state="disabled")
                    self._log(f"=== {'stopped' if stopped else 'finished'} "
                              f"— {nshows} shows, {nmovies} movies ===")
                    self._refresh_static_counts()
                elif kind == "error":
                    self.state_var.set("Error")
                    self.start_btn.configure(state="normal")
                    self.stop_btn.configure(state="disabled")
                    self._log("ERROR: " + msg[1])
                    messagebox.showerror("Scraper error", msg[1])
        except queue.Empty:
            pass
        self.root.after(150, self._poll)


def main():
    # make sure we run from the script's own folder so relative files resolve
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    root = tk.Tk()
    try:
        ttk.Style().theme_use("vista")
    except Exception:
        pass
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()

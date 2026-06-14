#!/usr/bin/env python3
"""
Simple GUI for enrich_tmdb.py — adds TMDB posters/overview/genres to the
catalog (the grouped file if present, else the flat one).

* Paste a TMDB key (v3 API key or v4 token), optionally save it to tmdb_key.txt.
* Start / Resume and Stop at any time. Resumable: items already enriched are
  skipped.

Run:  python enrich_gui.py
"""

import os
import json
import time
import queue
import threading
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox

import enrich_tmdb as et

SAVE_EVERY = 25


class App:
    def __init__(self, root):
        self.root = root
        root.title("TMDB Enrichment")
        root.geometry("760x560")
        root.minsize(640, 460)

        self.q = queue.Queue()
        self.stop_event = threading.Event()
        self.worker = None

        self.key_var = tk.StringVar(value=et.get_key() or "")
        self.save_key = tk.BooleanVar(value=True)
        self.force = tk.BooleanVar(value=False)

        self._build()
        self._refresh_counts()
        self.root.after(150, self._poll)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build(self):
        pad = {"padx": 10, "pady": 5}
        keyf = ttk.LabelFrame(self.root, text="TMDB key (v3 API key or v4 token)")
        keyf.pack(fill="x", **pad)
        row = ttk.Frame(keyf); row.pack(fill="x", padx=6, pady=6)
        ttk.Entry(row, textvariable=self.key_var, show="•").pack(
            side="left", fill="x", expand=True)
        ttk.Checkbutton(row, text="save to tmdb_key.txt",
                        variable=self.save_key).pack(side="left", padx=(8, 0))
        ttk.Checkbutton(keyf, text="Force re-fetch ALL (re-download every item, "
                                   "incl. already matched & unmatched)",
                        variable=self.force).pack(anchor="w", padx=8, pady=(0, 4))

        top = ttk.Frame(self.root); top.pack(fill="x", **pad)
        self.state_var = tk.StringVar(value="Idle")
        ttk.Label(top, text="Status:").grid(row=0, column=0, sticky="w")
        ttk.Label(top, textvariable=self.state_var,
                  font=("Segoe UI", 11, "bold")).grid(row=0, column=1, sticky="w",
                                                      padx=(4, 0))
        self.counts_var = tk.StringVar(value="")
        ttk.Label(top, textvariable=self.counts_var).grid(
            row=1, column=0, columnspan=4, sticky="w", pady=(2, 0))
        self.input_var = tk.StringVar(value="")
        ttk.Label(top, textvariable=self.input_var).grid(
            row=2, column=0, columnspan=4, sticky="w")

        cur = ttk.LabelFrame(self.root, text="Now matching")
        cur.pack(fill="x", **pad)
        self.current_var = tk.StringVar(value="-")
        ttk.Label(cur, textvariable=self.current_var,
                  font=("Segoe UI", 10, "bold")).pack(anchor="w", padx=8, pady=(6, 0))
        self.pbar = ttk.Progressbar(cur, mode="determinate")
        self.pbar.pack(fill="x", padx=8, pady=4)
        self.pct_var = tk.StringVar(value="")
        ttk.Label(cur, textvariable=self.pct_var).pack(anchor="w", padx=8,
                                                       pady=(0, 6))

        btns = ttk.Frame(self.root); btns.pack(fill="x", **pad)
        self.start_btn = ttk.Button(btns, text="▶  Start / Resume",
                                    command=self._start)
        self.start_btn.pack(side="left")
        self.stop_btn = ttk.Button(btns, text="■  Stop", command=self._stop,
                                   state="disabled")
        self.stop_btn.pack(side="left", padx=(8, 0))
        ttk.Button(btns, text="Open folder",
                   command=lambda: os.startfile(os.getcwd())).pack(side="right")

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
        if int(self.log.index("end-1c").split(".")[0]) > 400:
            self.log.delete("1.0", "100.0")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _refresh_counts(self):
        path = et.default_input()
        self.input_var.set("Enriching: " + path)
        try:
            cat = json.load(open(path, encoding="utf-8"))
            items = cat.get("shows", []) + cat.get("movies", [])
            bilingual = sum(1 for it in items
                            if isinstance(it.get("tmdb"), dict)
                            and "ar" in it["tmdb"])
            todo = sum(1 for it in items if et.needs_enrich(it, False))
            self.counts_var.set(
                f"{len(items)} items   |   bilingual-ready: {bilingual}   "
                f"|   need processing: {todo}")
        except Exception as e:
            self.counts_var.set("Could not read catalog: " + str(e))

    # ----- start / stop -----
    def _start(self):
        if self.worker and self.worker.is_alive():
            return
        key = self.key_var.get().strip()
        if not key:
            messagebox.showwarning("Key needed", "Paste your TMDB key first.")
            return
        if self.save_key.get():
            try:
                open("tmdb_key.txt", "w", encoding="utf-8").write(key)
            except Exception:
                pass
        self.stop_event.clear()
        self.start_btn.configure(state="disabled")
        self.stop_btn.configure(state="normal")
        self.state_var.set("Running")
        self._log("=== started ===")
        self.worker = threading.Thread(target=self._run, args=(key,), daemon=True)
        self.worker.start()

    def _stop(self):
        if self.worker and self.worker.is_alive():
            self.stop_event.set()
            self.state_var.set("Stopping…")
            self.stop_btn.configure(state="disabled")

    def _on_close(self):
        if self.worker and self.worker.is_alive():
            if not messagebox.askokcancel("Quit", "Enrichment running. Stop and quit?"):
                return
            self.stop_event.set()
            self.root.after(400, self._on_close)
            return
        self.root.destroy()

    # ----- worker -----
    def _run(self, key):
        try:
            session = et.make_session(key)
            if not et.api_get(session, "/configuration"):
                self.q.put(("error", "Could not reach TMDB or the key is invalid."))
                return
            self.q.put(("log", "key OK"))

            path = et.default_input()
            cat = json.load(open(path, encoding="utf-8"))
            items = ([("tv", s) for s in cat.get("shows", [])]
                     + [("movie", m) for m in cat.get("movies", [])])
            force = self.force.get()
            todo = [(k, it) for k, it in items if et.needs_enrich(it, force)]
            self.q.put(("total", len(todo)))
            self.q.put(("log", f"{len(items)} items, {len(todo)} to enrich"
                               f"{' (force)' if force else ''}"))

            matched = unmatched = 0
            for i, (kind, item) in enumerate(todo, 1):
                if self.stop_event.is_set():
                    break
                self.q.put(("cur", item.get("title", ""), i, len(todo)))
                res, conf, qy = et.search_best(session, item, kind)
                if res and conf >= et.MIN_CONFIDENCE and res.get("poster_path"):
                    item["tmdb"] = et.build_tmdb_block(session, res, kind, conf, qy)
                    matched += 1
                    self.q.put(("log", f"OK  ({conf:.2f})  {item.get('title','')[:38]}"))
                else:
                    item["tmdb"] = None
                    unmatched += 1
                    self.q.put(("log", f"--  no match   {item.get('title','')[:38]}"))
                if i % SAVE_EVERY == 0:
                    et.save(cat, path)
                    self.q.put(("saved", matched, unmatched, i))
            et.save(cat, path)
            self.q.put(("finished", self.stop_event.is_set(), matched, unmatched))
        except Exception as e:
            self.q.put(("error", str(e)))

    # ----- queue pump -----
    def _poll(self):
        try:
            while True:
                m = self.q.get_nowait()
                k = m[0]
                if k == "log":
                    self._log(m[1])
                elif k == "total":
                    self.pbar.configure(maximum=max(1, m[1]), value=0)
                elif k == "cur":
                    title, i, total = m[1], m[2], m[3]
                    self.current_var.set(f"{title}   ({i} / {total})")
                    self.pbar.configure(value=i - 1)
                    self.pct_var.set(f"{i-1} of {total} done this run")
                elif k == "saved":
                    matched, unmatched, i = m[1], m[2], m[3]
                    self.pbar.configure(value=i)
                    self._refresh_counts()
                elif k == "finished":
                    stopped, matched, unmatched = m[1], m[2], m[3]
                    self.state_var.set("Stopped" if stopped else "Finished ✓")
                    self.current_var.set("-")
                    self.start_btn.configure(state="normal")
                    self.stop_btn.configure(state="disabled")
                    self._log(f"=== {'stopped' if stopped else 'done'} — "
                              f"matched {matched}, unmatched {unmatched} ===")
                    self._refresh_counts()
                elif k == "error":
                    self.state_var.set("Error")
                    self.start_btn.configure(state="normal")
                    self.stop_btn.configure(state="disabled")
                    self._log("ERROR: " + m[1])
                    messagebox.showerror("TMDB error", m[1])
        except queue.Empty:
            pass
        self.root.after(150, self._poll)


def main():
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

#!/usr/bin/env python3
"""Live progress viewer for the WCOFlix TMDB enrichment run.

No third-party deps (stdlib Tkinter only). Run it any time while
`dart run tool/wcoflix_enrich.dart` is going:

    python tool/enrich_gui.py

It reads two files, preferring whichever is fresher:
  * tool/enrich_progress.json  -> exact {target, processed, matched, running}
  * assets/wcoflix_catalog.json -> checkpoint written every 100 titles
    (matched count + timestamp), so even an already-running enrich is visible.
"""
import json
import os
import time
import tkinter as tk
from tkinter import ttk
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PROGRESS = os.path.join(HERE, "enrich_progress.json")
CATALOG = os.path.join(ROOT, "assets", "wcoflix_catalog.json")

# The unique-title target the enricher prints ("N unique titles to enrich").
# The progress file overrides this once a run that supports it starts.
FALLBACK_TARGET = 11671

INK = "#0f1430"
BG = "#0b0e1a"
CARD = "#151a2e"
ACCENT = "#7c5cff"
GREEN = "#39d98a"
MUTE = "#8a93b2"
WHITE = "#eef1fb"


def _read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _parse_iso(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


class App:
    def __init__(self, root):
        self.root = root
        root.title("WCOFlix · TMDB Enrichment")
        root.configure(bg=BG)
        root.geometry("560x420")
        root.minsize(520, 400)

        self.samples = []          # (monotonic_time, processed)
        self.start_time = time.monotonic()

        style = ttk.Style()
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("bar.Horizontal.TProgressbar", troughcolor=CARD,
                        background=ACCENT, bordercolor=CARD, thickness=26)

        tk.Label(root, text="TMDB ENRICHMENT", bg=BG, fg=MUTE,
                 font=("Segoe UI", 11, "bold")).pack(pady=(20, 0))

        self.count_lbl = tk.Label(root, text="—", bg=BG, fg=WHITE,
                                  font=("Segoe UI", 40, "bold"))
        self.count_lbl.pack(pady=(4, 0))
        self.sub_lbl = tk.Label(root, text="waiting for data…", bg=BG, fg=MUTE,
                                font=("Segoe UI", 11))
        self.sub_lbl.pack()

        self.bar = ttk.Progressbar(root, style="bar.Horizontal.TProgressbar",
                                   length=480, maximum=1000)
        self.bar.pack(pady=18)

        grid = tk.Frame(root, bg=BG)
        grid.pack(pady=4)
        self.stat = {}
        for i, (key, label) in enumerate([
            ("matched", "Matched"), ("rate", "Match rate"),
            ("speed", "Speed"), ("eta", "ETA"),
        ]):
            cell = tk.Frame(grid, bg=CARD, padx=18, pady=10)
            cell.grid(row=i // 2, column=i % 2, padx=8, pady=8, sticky="nsew")
            tk.Label(cell, text=label.upper(), bg=CARD, fg=MUTE,
                     font=("Segoe UI", 8, "bold")).pack(anchor="w")
            v = tk.Label(cell, text="—", bg=CARD, fg=WHITE,
                         font=("Segoe UI", 15, "bold"))
            v.pack(anchor="w")
            self.stat[key] = v

        self.status_lbl = tk.Label(root, text="", bg=BG, fg=MUTE,
                                   font=("Segoe UI", 9))
        self.status_lbl.pack(side="bottom", pady=10)

        self.tick()

    def _load(self):
        """Return (target, processed, matched, running, updated_dt, source)."""
        prog = _read_json(PROGRESS)
        cat = _read_json(CATALOG)
        prog_dt = _parse_iso(prog["updated_at"]) if prog else None
        cat_dt = _parse_iso(cat["generated_at"]) if cat else None

        # Prefer the progress file only if it is at least as fresh as the
        # catalog checkpoint (an old run may leave a stale progress file).
        if prog and (not cat_dt or (prog_dt and prog_dt >= cat_dt)):
            return (prog.get("target", FALLBACK_TARGET), prog.get("processed", 0),
                    prog.get("matched", 0), prog.get("running", False),
                    prog_dt, "progress")
        if cat:
            matched = cat.get("total", len(cat.get("items", {})))
            # No exact 'processed' from the checkpoint; matched is the live proxy.
            return (FALLBACK_TARGET, matched, matched, None, cat_dt, "catalog")
        return (FALLBACK_TARGET, 0, 0, None, None, "none")

    def tick(self):
        target, processed, matched, running, updated, source = self._load()
        now = time.monotonic()

        if source == "none":
            self.sub_lbl.config(text="No output yet — start the enrich run.")
            self.root.after(1500, self.tick)
            return

        # progress bar: processed (exact) or matched (checkpoint proxy)
        shown = processed if source == "progress" else matched
        frac = min(shown / target, 1.0) if target else 0
        self.bar["value"] = frac * 1000

        self.count_lbl.config(text=f"{matched:,}")
        self.sub_lbl.config(text=f"of {target:,} titles  ·  {frac*100:.1f}%")
        self.stat["matched"].config(text=f"{matched:,}")

        rate = (matched / processed * 100) if processed else 0
        self.stat["rate"].config(text=f"{rate:.0f}%", fg=GREEN if rate >= 80 else WHITE)

        # speed + ETA from a rolling window of samples
        self.samples.append((now, shown))
        self.samples = [s for s in self.samples if now - s[0] <= 30]
        speed = 0.0
        if len(self.samples) >= 2:
            dt = self.samples[-1][0] - self.samples[0][0]
            dv = self.samples[-1][1] - self.samples[0][1]
            speed = dv / dt if dt > 0 else 0
        self.stat["speed"].config(
            text=f"{speed:.1f}/s" if speed > 0 else "—")
        remaining = max(target - shown, 0)
        if speed > 0.05 and remaining > 0:
            eta = int(remaining / speed)
            self.stat["eta"].config(text=f"{eta//60}m {eta%60:02d}s")
        else:
            self.stat["eta"].config(text="—")

        # freshness / running state
        stale = updated and (datetime.now(timezone.utc) - updated).total_seconds() > 25
        if running is False and source == "progress":
            state, col = "✓ complete", GREEN
        elif frac >= 1.0:
            state, col = "✓ complete", GREEN
        elif stale:
            state, col = "idle (no recent writes)", MUTE
        else:
            state, col = "● running", GREEN
        upd = updated.astimezone().strftime("%H:%M:%S") if updated else "—"
        self.status_lbl.config(text=f"{state}   ·   {source} file   ·   updated {upd}",
                               fg=col)
        self.root.after(1500, self.tick)


if __name__ == "__main__":
    root = tk.Tk()
    App(root)
    root.mainloop()

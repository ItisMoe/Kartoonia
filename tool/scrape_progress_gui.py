"""Live progress window for the wcoflix title-verification scrape.

Tails the scrape's console output file and shows: a progress bar
(checked / total pages), dead + challenge counters, a rate/ETA estimate, the
raw log, and — once the run finishes — the full list of removed titles (read
from dead_titles.txt, which the scraper writes at the end).

Run:
    python tool/scrape_progress_gui.py <path-to-scrape-output-file> [dead_titles.txt]
If no argument is given it expects `dead_titles.txt` in the working directory
and shows only the final removals (useful after the fact).
"""

import os
import re
import sys
import time
import tkinter as tk
from tkinter import ttk

RE_TOTAL = re.compile(r"verifying (\d+) unique title pages")
RE_PROGRESS = re.compile(r"(\d+) checked, (\d+) dead, (\d+) challenges")
RE_DONE = re.compile(r"done in (\d+)s: (\d+) dead of (\d+)")
RE_CATALOG = re.compile(r"catalog: (\d+) -> (\d+)")


class ScrapeProgressUI:
    def __init__(self, root: tk.Tk, log_path: str | None, dead_path: str):
        self.root = root
        self.log_path = log_path
        self.dead_path = dead_path
        self.total = 0
        self.finished = False
        self._log_size = 0
        self._dead_loaded = False
        # Rate from deltas between LIVE progress lines (the first read replays
        # the whole backlog at once, which would make an elapsed-time rate
        # absurdly optimistic).
        self._last_mark: tuple[float, int] | None = None
        self._rate = 0.0

        root.title("WCOFlix Title Verification")
        root.geometry("880x640")
        root.configure(bg="#1e1e1e")

        def label(parent, text, size=11, color="#ddd"):
            return tk.Label(parent, text=text, fg=color, bg="#1e1e1e",
                            font=("Segoe UI", size))

        head = tk.Frame(root, bg="#1e1e1e")
        head.pack(fill="x", padx=14, pady=(12, 4))
        self.title_lbl = label(head, "Waiting for scrape output…", 13, "#fff")
        self.title_lbl.pack(anchor="w")

        self.bar = ttk.Progressbar(root, maximum=100, value=0)
        self.bar.pack(fill="x", padx=14, pady=6)

        stats = tk.Frame(root, bg="#1e1e1e")
        stats.pack(fill="x", padx=14)
        self.checked_lbl = label(stats, "checked: 0 / ?")
        self.checked_lbl.pack(side="left")
        self.dead_lbl = label(stats, "   removed: 0", color="#ff8a80")
        self.dead_lbl.pack(side="left")
        self.chal_lbl = label(stats, "   challenges: 0", color="#ffd54f")
        self.chal_lbl.pack(side="left")
        self.eta_lbl = label(stats, "   ETA: —", color="#8bc34a")
        self.eta_lbl.pack(side="left")

        label(root, "Log", 10, "#888").pack(anchor="w", padx=14, pady=(10, 0))
        logf = tk.Frame(root, bg="#1e1e1e")
        logf.pack(fill="both", expand=True, padx=14, pady=(2, 6))
        self.log = tk.Text(logf, height=8, bg="#111", fg="#bbb",
                           font=("Consolas", 9), state="disabled", wrap="none")
        sb = ttk.Scrollbar(logf, command=self.log.yview)
        self.log.configure(yscrollcommand=sb.set)
        sb.pack(side="right", fill="y")
        self.log.pack(fill="both", expand=True)

        label(root, "Removed titles (dead on wcoflix.tv)", 10, "#888").pack(
            anchor="w", padx=14)
        deadf = tk.Frame(root, bg="#1e1e1e")
        deadf.pack(fill="both", expand=True, padx=14, pady=(2, 12))
        self.dead_list = tk.Text(deadf, height=10, bg="#111", fg="#ff8a80",
                                 font=("Consolas", 9), state="disabled",
                                 wrap="none")
        sb2 = ttk.Scrollbar(deadf, command=self.dead_list.yview)
        self.dead_list.configure(yscrollcommand=sb2.set)
        sb2.pack(side="right", fill="y")
        self.dead_list.pack(fill="both", expand=True)

        root.after(300, self.tick)

    # ------------------------------------------------------------------
    def _append(self, widget: tk.Text, text: str):
        widget.configure(state="normal")
        widget.insert("end", text)
        widget.see("end")
        widget.configure(state="disabled")

    def tick(self):
        try:
            self._read_log()
            self._read_dead()
        except Exception:
            pass
        self.root.after(1000, self.tick)

    def _read_log(self):
        if not self.log_path or not os.path.exists(self.log_path):
            return
        size = os.path.getsize(self.log_path)
        if size == self._log_size:
            return
        with open(self.log_path, encoding="utf-8", errors="replace") as f:
            f.seek(self._log_size)
            new = f.read()
        self._log_size = size
        if new.strip():
            self._append(self.log, new if new.endswith("\n") else new + "\n")

        m = RE_TOTAL.search(new)
        if m:
            self.total = int(m.group(1))
            self.title_lbl.config(
                text=f"Verifying {self.total} title pages on wcoflix.tv")
            self.bar.configure(maximum=self.total)

        for m in RE_PROGRESS.finditer(new):
            checked, dead, chal = map(int, m.groups())
            self.bar.configure(value=checked)
            pct = f" ({checked * 100 // self.total}%)" if self.total else ""
            self.checked_lbl.config(
                text=f"checked: {checked} / {self.total or '?'}{pct}")
            self.dead_lbl.config(text=f"   removed: {dead}")
            self.chal_lbl.config(text=f"   challenges: {chal}")
            now = time.time()
            if self._last_mark is not None:
                dt, dn = now - self._last_mark[0], checked - self._last_mark[1]
                if dt > 1 and dn > 0:
                    self._rate = dn / dt
            self._last_mark = (now, checked)
            if self.total and self._rate > 0:
                eta = (self.total - checked) / self._rate
                self.eta_lbl.config(
                    text=f"   ETA: {int(eta // 60)}m {int(eta % 60)}s "
                         f"({self._rate:.0f}/s)")

        m = RE_DONE.search(new)
        if m:
            self.finished = True
            secs, dead, total = map(int, m.groups())
            self.bar.configure(value=self.total or total)
            self.title_lbl.config(
                text=f"FINISHED in {secs // 60}m {secs % 60}s — "
                     f"{dead} dead titles removed of {total}")
            self.eta_lbl.config(text="   ETA: done")
        m = RE_CATALOG.search(new)
        if m:
            self._append(
                self.log,
                f">>> enriched catalog pruned: {m.group(1)} -> {m.group(2)}\n")

    def _read_dead(self):
        if self._dead_loaded or not os.path.exists(self.dead_path):
            return
        # The scraper writes this file once at the end of the run.
        with open(self.dead_path, encoding="utf-8", errors="replace") as f:
            lines = f.read().strip()
        self._dead_loaded = True
        self._append(self.dead_list,
                     lines + "\n" if lines else "(nothing removed)\n")


if __name__ == "__main__":
    log = sys.argv[1] if len(sys.argv) > 1 else None
    dead = sys.argv[2] if len(sys.argv) > 2 else "dead_titles.txt"
    tk_root = tk.Tk()
    ScrapeProgressUI(tk_root, log, dead)
    tk_root.mainloop()

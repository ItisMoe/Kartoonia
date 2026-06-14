#!/usr/bin/env python3
"""
Speed-test GUI for the simplified Stardima resolver.

You paste a Stardima *play* URL, e.g.
    https://www.stardima.com/tvshow/video-309/play/15628
and it pulls the playable server links in real time, reporting HOW LONG each
stage took:

    page    -> fetch the play page + find the hyperwatching iframe code
    servers -> resolve the playable server links
    TOTAL

Server links are clickable (open in your browser) and can be played in-app
through the VLC player. Run:
    python stardima_speed_gui.py
"""

import os
import time
import threading
import webbrowser
import tkinter as tk
from tkinter import ttk, messagebox

import stardima_resolver as sr
import stardima_player as splayer

DEFAULT_URL = "https://www.stardima.com/tvshow/video-309/play/15628"


def timed_resolve(play_url):
    """Replicates resolver.resolve() but records per-stage timings."""
    timings = {}
    t0 = time.time()

    # 1) play page -> hyperwatching iframe code
    t = time.time()
    code = sr._hyperwatching_code(play_url)
    timings["page"] = time.time() - t
    if not code:
        return {"error": "No hyperwatching iframe found on that play page.",
                "timings": timings, "total": time.time() - t0}

    # 2) code -> playable server links
    t = time.time()
    srv = sr.servers_for_code(code)
    timings["servers"] = time.time() - t

    return {
        "play_url": play_url,
        "code": code,
        "servers": srv,
        "timings": timings,
        "total": time.time() - t0,
    }


class App:
    def __init__(self, root):
        self.root = root
        root.title("Stardima Link Speed Test")
        root.geometry("720x540")
        root.minsize(620, 460)
        self.busy = False
        self._build()

    def _build(self):
        pad = {"padx": 10, "pady": 6}
        f = ttk.Frame(self.root); f.pack(fill="x", **pad)
        ttk.Label(f, text="Play URL:").grid(row=0, column=0, sticky="w")
        self.url = tk.StringVar(value=DEFAULT_URL)
        e = ttk.Entry(f, textvariable=self.url, width=60)
        e.grid(row=0, column=1, sticky="we", padx=4)
        e.bind("<Return>", lambda *_: self._go())
        f.columnconfigure(1, weight=1)

        row2 = ttk.Frame(self.root); row2.pack(fill="x", **pad)
        ttk.Label(row2, text="Paste a Stardima episode play URL and hit Get links.",
                  foreground="#666").pack(side="left")
        self.go_btn = ttk.Button(row2, text="⚡  Get links", command=self._go)
        self.go_btn.pack(side="right")

        # big timing readout
        self.total_var = tk.StringVar(value="—")
        ttk.Label(self.root, textvariable=self.total_var,
                  font=("Segoe UI", 22, "bold")).pack(anchor="w", padx=12)
        self.status_var = tk.StringVar(value="Ready.")
        self.status_lbl = ttk.Label(self.root, textvariable=self.status_var)
        self.status_lbl.pack(anchor="w", padx=12)

        # per-stage timing
        tf = ttk.LabelFrame(self.root, text="Stage timing (seconds)")
        tf.pack(fill="x", **pad)
        self.stage_var = tk.StringVar(value="")
        ttk.Label(tf, textvariable=self.stage_var, font=("Consolas", 10),
                  justify="left").pack(anchor="w", padx=8, pady=6)

        # servers (clickable)
        sf = ttk.LabelFrame(self.root, text="Server links (click to open)")
        sf.pack(fill="both", expand=True, **pad)
        self.srv_frame = ttk.Frame(sf)
        self.srv_frame.pack(fill="both", expand=True, padx=6, pady=6)

    def _set_status(self, msg, color=None):
        self.status_var.set(msg)
        try:
            self.status_lbl.configure(foreground=color or "")
        except Exception:
            pass

    def _clear_servers(self):
        for w in self.srv_frame.winfo_children():
            w.destroy()

    def _add_link(self, label, url):
        """One link row: [▶ Play in app] [🔗 open in browser] + the url."""
        if not url:
            return
        row = ttk.Frame(self.srv_frame)
        row.pack(fill="x", anchor="w", pady=2)

        play = ttk.Button(row, text="▶ Play",
                          command=lambda u=url, l=label: self._play(u, l))
        play.pack(side="left", padx=(0, 6))

        lbl = tk.Label(row, text=f"🔗 {label}", fg="#2563eb",
                       cursor="hand2", font=("Segoe UI", 10, "underline"))
        lbl.pack(side="left")
        lbl.bind("<Button-1>", lambda *_: webbrowser.open(url))

        sub = tk.Label(self.srv_frame, text="     " + url, fg="#888",
                       font=("Consolas", 8))
        sub.pack(anchor="w")

    def _play(self, url, label):
        """Open the in-app python-vlc player for this embed link."""
        try:
            splayer.open_player(self.root, url, label=label)
        except Exception as e:
            messagebox.showerror("Player error", str(e))

    def _go(self):
        if self.busy:
            return
        url = self.url.get().strip()
        if not url.startswith("http"):
            self._set_status("✗ Enter a full play URL (https://…).", "red")
            return
        self.busy = True
        self.go_btn.configure(state="disabled")
        self.total_var.set("…")
        self._set_status("resolving…", "gray")
        self._clear_servers()
        self.stage_var.set("")
        threading.Thread(target=self._work, args=(url,), daemon=True).start()

    def _work(self, url):
        try:
            d = timed_resolve(url)
        except Exception as e:
            d = {"error": str(e), "timings": {}, "total": 0}
        self.root.after(0, self._show, d)

    def _show(self, d):
        self.busy = False
        self.go_btn.configure(state="normal")
        t = d.get("timings", {})
        lines = [f"{k:9}: {t[k]:.2f}s" for k in ("page", "servers") if k in t]
        self.stage_var.set("\n".join(lines) or "—")
        self.total_var.set(f"{d.get('total', 0):.2f}s  total")

        if d.get("error"):
            self._set_status("✗ " + d["error"], "red")
            return
        n = len(d.get("servers", []))
        self._set_status(
            f"✓ {n} server link(s) found   (iframe code {d.get('code', '?')})",
            "green" if n else "orange")

        for s in d.get("servers", []):
            self._add_link(s["server"], s["embed_url"])
        if not n:
            tk.Label(self.srv_frame, text="No Stardima server links for this one.",
                     fg="#aa6600").pack(anchor="w")


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
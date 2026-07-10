"""Minimal URL video player UI (tkinter + VLC).

Paste any direct video URL (mp4, m3u8/HLS, mkv, ...) and press Play.

Made for verifying Kartoonia stream URLs by hand — the Referer / User-Agent
fields default to the exact values the WCOFlix getvid CDN requires
(kWcoflixMediaHeaders in lib/services/wcoflix/wcoflix_config.dart), because
those tokens are bound to the UA that fetched them. Clear both fields to play
an ordinary URL with no custom headers.

Requirements:
    1. Install VLC (64-bit, matching your Python's bitness): https://videolan.org
    2. pip install python-vlc

Run:
    python tool/url_player_ui.py [optional-url]
"""

import sys
import tkinter as tk
from tkinter import messagebox, ttk

try:
    import vlc
except ImportError:
    print("python-vlc is not installed. Run:  pip install python-vlc")
    sys.exit(1)

# Same values as kWcoflixUserAgent / kWcoflixMediaHeaders in the app. The getvid
# CDN binds its tokens to the UA, so this must match the app's UA exactly
# (Chrome/149 — Chrome/147 is now rejected with a 403).
DEFAULT_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
)
DEFAULT_REFERER = "https://embed.wcostream.com/"


class PlayerUI:
    def __init__(self, root: tk.Tk, initial_url: str = ""):
        self.root = root
        root.title("URL Player")
        root.geometry("960x640")
        root.configure(bg="#1e1e1e")

        self.instance = vlc.Instance("--quiet")
        self.player = self.instance.media_player_new()
        self._dragging_seek = False
        self._audio_pending = False

        # --- top bar: URL + headers -------------------------------------
        top = tk.Frame(root, bg="#1e1e1e")
        top.pack(fill="x", padx=8, pady=(8, 4))

        tk.Label(top, text="URL", fg="#ddd", bg="#1e1e1e").grid(row=0, column=0, sticky="w")
        self.url_var = tk.StringVar(value=initial_url)
        url_entry = ttk.Entry(top, textvariable=self.url_var)
        url_entry.grid(row=0, column=1, sticky="ew", padx=6)
        url_entry.bind("<Return>", lambda _e: self.play())

        tk.Label(top, text="Referer", fg="#888", bg="#1e1e1e").grid(row=1, column=0, sticky="w")
        self.ref_var = tk.StringVar(value=DEFAULT_REFERER)
        ttk.Entry(top, textvariable=self.ref_var).grid(row=1, column=1, sticky="ew", padx=6, pady=2)

        tk.Label(top, text="User-Agent", fg="#888", bg="#1e1e1e").grid(row=2, column=0, sticky="w")
        self.ua_var = tk.StringVar(value=DEFAULT_UA)
        ttk.Entry(top, textvariable=self.ua_var).grid(row=2, column=1, sticky="ew", padx=6)

        ttk.Button(top, text="Play", command=self.play).grid(row=0, column=2, rowspan=3, sticky="ns", padx=(4, 0))
        top.columnconfigure(1, weight=1)

        # --- video surface ----------------------------------------------
        self.video = tk.Frame(root, bg="black")
        self.video.pack(fill="both", expand=True, padx=8)

        # --- transport controls ------------------------------------------
        bar = tk.Frame(root, bg="#1e1e1e")
        bar.pack(fill="x", padx=8, pady=6)

        self.pp_btn = ttk.Button(bar, text="Pause", width=8, command=self.toggle_pause)
        self.pp_btn.pack(side="left")
        ttk.Button(bar, text="Stop", width=6, command=self.stop).pack(side="left", padx=4)
        ttk.Button(bar, text="-10s", width=5, command=lambda: self.skip(-10)).pack(side="left")
        ttk.Button(bar, text="+10s", width=5, command=lambda: self.skip(10)).pack(side="left", padx=4)

        self.time_lbl = tk.Label(bar, text="--:-- / --:--", fg="#ddd", bg="#1e1e1e", width=15)
        self.time_lbl.pack(side="right")

        self.seek = ttk.Scale(bar, from_=0, to=1000, orient="horizontal", command=self._on_seek_move)
        self.seek.pack(side="left", fill="x", expand=True, padx=8)
        self.seek.bind("<ButtonPress-1>", lambda _e: setattr(self, "_dragging_seek", True))
        self.seek.bind("<ButtonRelease-1>", self._on_seek_release)

        tk.Label(bar, text="Vol", fg="#888", bg="#1e1e1e").pack(side="left")
        self.vol = ttk.Scale(bar, from_=0, to=100, orient="horizontal", length=90,
                             command=lambda v: self.player.audio_set_volume(int(float(v))))
        self.vol.set(80)
        self.vol.pack(side="left", padx=(2, 0))

        self.status = tk.Label(root, text="Enter a URL and press Play", anchor="w",
                               fg="#888", bg="#1e1e1e")
        self.status.pack(fill="x", padx=8, pady=(0, 6))

        root.after(500, self._tick)
        root.protocol("WM_DELETE_WINDOW", self._close)

    # --- actions ---------------------------------------------------------
    def play(self):
        url = self.url_var.get().strip()
        if not url:
            messagebox.showwarning("URL Player", "Paste a video URL first.")
            return

        media = self.instance.media_new(url)
        ua = self.ua_var.get().strip()
        ref = self.ref_var.get().strip()
        if ua:
            media.add_option(f":http-user-agent={ua}")
        if ref:
            media.add_option(f":http-referrer={ref}")
        media.add_option(":network-caching=3000")

        self.player.set_media(media)
        self._attach_video_surface()
        self.player.play()
        # Volume/mute must be (re)applied once the audio output exists — done in
        # _tick. Windows persists per-app mute in the Volume Mixer, so a muted
        # python.exe session would otherwise silence every future run.
        self._audio_pending = True
        self.pp_btn.config(text="Pause")
        self.status.config(text=f"Opening {url[:90]}...")

    def _attach_video_surface(self):
        wid = self.video.winfo_id()
        if sys.platform.startswith("win"):
            self.player.set_hwnd(wid)
        elif sys.platform == "darwin":
            self.player.set_nsobject(wid)
        else:
            self.player.set_xwindow(wid)

    def toggle_pause(self):
        if self.player.is_playing():
            self.player.pause()
            self.pp_btn.config(text="Play")
        else:
            self.player.play()
            self.pp_btn.config(text="Pause")

    def stop(self):
        self.player.stop()
        self.pp_btn.config(text="Play")
        self.status.config(text="Stopped")

    def skip(self, seconds: int):
        t = self.player.get_time()
        if t >= 0:
            self.player.set_time(max(0, t + seconds * 1000))

    # --- seek bar / clock -------------------------------------------------
    def _on_seek_move(self, _val):
        pass  # position only applied on release, to avoid stutter while dragging

    def _on_seek_release(self, _e):
        self._dragging_seek = False
        length = self.player.get_length()
        if length > 0:
            self.player.set_time(int(length * self.seek.get() / 1000))

    @staticmethod
    def _fmt(ms: int) -> str:
        if ms < 0:
            return "--:--"
        s = ms // 1000
        return f"{s // 3600}:{s % 3600 // 60:02}:{s % 60:02}" if s >= 3600 else f"{s // 60}:{s % 60:02}"

    def _tick(self):
        st = self.player.get_state()
        if st == vlc.State.Error:
            self.status.config(text="VLC could not open this URL (check headers / token freshness)")
        elif st == vlc.State.Playing:
            self.status.config(text="Playing")
            if self._audio_pending:
                self._audio_pending = False
                self.player.audio_set_mute(False)
                self.player.audio_set_volume(int(self.vol.get()))
        t, length = self.player.get_time(), self.player.get_length()
        self.time_lbl.config(text=f"{self._fmt(t)} / {self._fmt(length)}")
        if not self._dragging_seek and length > 0 and t >= 0:
            self.seek.set(t * 1000 / length)
        self.root.after(500, self._tick)

    def _close(self):
        self.player.stop()
        self.player.release()
        self.instance.release()
        self.root.destroy()


if __name__ == "__main__":
    tk_root = tk.Tk()
    PlayerUI(tk_root, sys.argv[1] if len(sys.argv) > 1 else "")
    tk_root.mainloop()

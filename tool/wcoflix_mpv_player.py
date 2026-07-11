"""Everything-mode repro player (tkinter + libmpv) — the SAME engine as the app.

The Kartoonia app plays video through media_kit, which is libmpv. The older
`url_player_ui.py` tool uses VLC — a different decode/render stack — so it can't
tell you what *the app's* player will do with a stream. This tool drives libmpv
with the exact configuration `lib/services/player_service.dart` applies:

    ensureCreated():   hls-bitrate=max, alang=ara,ar
    open(wcoflix):     hwdec=no        (Everything mode, v2.2.6 fix)
    open(other):       hwdec=auto-safe (media_kit's Android default)
    Media headers:     ALL headers (incl. User-Agent) passed via
                       http-header-fields, exactly like media_kit's NativePlayer

Paste a getvid/HLS URL (get one with `dart run tool/wcoflix_codec_probe.dart`),
keep the default Referer / User-Agent (they must match kWcoflixMediaHeaders —
the getvid CDN binds its tokens to the UA), pick a hwdec mode, press Play.

The **hwdec** dropdown can be changed WHILE PLAYING: libmpv re-selects the
decoder immediately, so you can A/B hardware vs software decode mid-stream and
watch the picture garble/recover. The log pane shows every decoder decision
(`vd`/`vo`/`hwdec` messages) plus warnings/errors, and the status bar shows the
live `hwdec-current` + video-params so you can see exactly which decoder and
pixel format produced the frames on screen.

Requirements:
    1. pip install python-mpv
    2. libmpv-2.dll — searched in this order:
         $LIBMPV_PATH, next to this script, Stremio's install dir, PATH.
       (A Stremio install already provides one; or download a libmpv build from
        https://sourceforge.net/projects/mpv-player-windows/files/libmpv/)

Run:
    python tool/wcoflix_mpv_player.py [optional-url]
"""

import os
import queue
import sys
from pathlib import Path

# --- locate libmpv BEFORE importing python-mpv --------------------------------
def _prepare_libmpv():
    if not sys.platform.startswith("win"):
        return  # non-Windows: rely on the system loader
    names = ("libmpv-2.dll", "mpv-2.dll", "mpv-1.dll")
    here = Path(__file__).resolve().parent
    candidates = []
    if os.environ.get("LIBMPV_PATH"):
        p = Path(os.environ["LIBMPV_PATH"])
        candidates.append(p if p.is_dir() else p.parent)
    candidates.append(here)
    local = os.environ.get("LOCALAPPDATA")
    if local:
        candidates.append(Path(local) / "Programs" / "Stremio")
    for d in candidates:
        if any((d / n).exists() for n in names):
            os.add_dll_directory(str(d))
            os.environ["PATH"] = f"{d};{os.environ['PATH']}"
            return
    # else: hope it's already on PATH


_prepare_libmpv()

try:
    import mpv
except (ImportError, OSError) as e:
    print("Could not load python-mpv / libmpv-2.dll:", e)
    print("  1. pip install python-mpv")
    print("  2. put libmpv-2.dll next to this script, or set LIBMPV_PATH")
    sys.exit(1)

import tkinter as tk
from tkinter import messagebox, ttk

# Same values as kWcoflixUserAgent / kWcoflixMediaHeaders in
# lib/services/wcoflix/wcoflix_config.dart. The getvid CDN binds its tokens to
# the UA, so this must match the app's UA exactly.
DEFAULT_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
)
DEFAULT_REFERER = "https://embed.wcostream.com/"

# The two decode modes the app uses (PlayerService._applyHwdec):
#   'no'        — Everything mode since v2.2.6 (software decode)
#   'auto-safe' — every other catalog; media_kit's Android default, and the
#                 mode Everything ran in BEFORE v2.2.6 (garbled on some boxes)
HWDEC_MODES = ["no (app: Everything mode, v2.2.6+)", "auto-safe (app: default / pre-fix)"]


def _hwdec_value(label: str) -> str:
    return label.split(" ", 1)[0]


class PlayerUI:
    def __init__(self, root: tk.Tk, initial_url: str = ""):
        self.root = root
        root.title("WCOFlix mpv Player (app engine repro)")
        root.geometry("1100x760")
        root.configure(bg="#1e1e1e")
        self._log_q: "queue.Queue[str]" = queue.Queue()
        self._dragging_seek = False

        # --- top bar: URL + headers + hwdec -------------------------------
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

        tk.Label(top, text="hwdec", fg="#888", bg="#1e1e1e").grid(row=3, column=0, sticky="w")
        self.hwdec_var = tk.StringVar(value=HWDEC_MODES[0])
        hw = ttk.Combobox(top, textvariable=self.hwdec_var, values=HWDEC_MODES, state="readonly")
        hw.grid(row=3, column=1, sticky="w", padx=6, pady=2)
        hw.configure(width=44)
        # Applying hwdec mid-playback makes libmpv re-select the decoder on the
        # fly — the fastest way to A/B garbled vs correct frames on one stream.
        hw.bind("<<ComboboxSelected>>", lambda _e: self._apply_hwdec(live=True))

        ttk.Button(top, text="Play", command=self.play).grid(
            row=0, column=2, rowspan=4, sticky="ns", padx=(4, 0))
        top.columnconfigure(1, weight=1)

        # --- video surface -------------------------------------------------
        self.video = tk.Frame(root, bg="black")
        self.video.pack(fill="both", expand=True, padx=8)

        # --- transport controls ---------------------------------------------
        bar = tk.Frame(root, bg="#1e1e1e")
        bar.pack(fill="x", padx=8, pady=6)

        self.pp_btn = ttk.Button(bar, text="Pause", width=8, command=self.toggle_pause)
        self.pp_btn.pack(side="left")
        ttk.Button(bar, text="Stop", width=6, command=self.stop).pack(side="left", padx=4)
        ttk.Button(bar, text="-10s", width=5, command=lambda: self.skip(-10)).pack(side="left")
        ttk.Button(bar, text="+10s", width=5, command=lambda: self.skip(10)).pack(side="left", padx=4)

        self.time_lbl = tk.Label(bar, text="--:-- / --:--", fg="#ddd", bg="#1e1e1e", width=15)
        self.time_lbl.pack(side="right")

        self.seek = ttk.Scale(bar, from_=0, to=1000, orient="horizontal")
        self.seek.pack(side="left", fill="x", expand=True, padx=8)
        self.seek.bind("<ButtonPress-1>", lambda _e: setattr(self, "_dragging_seek", True))
        self.seek.bind("<ButtonRelease-1>", self._on_seek_release)

        tk.Label(bar, text="Vol", fg="#888", bg="#1e1e1e").pack(side="left")
        self.vol = ttk.Scale(bar, from_=0, to=100, orient="horizontal", length=90,
                             command=self._on_volume)
        self.vol.set(80)
        self.vol.pack(side="left", padx=(2, 0))

        # --- decode status + log pane ---------------------------------------
        self.status = tk.Label(root, text="Enter a URL and press Play", anchor="w",
                               fg="#8bc34a", bg="#1e1e1e", font=("Consolas", 9))
        self.status.pack(fill="x", padx=8)

        logf = tk.Frame(root, bg="#1e1e1e")
        logf.pack(fill="x", padx=8, pady=(2, 8))
        self.log = tk.Text(logf, height=9, bg="#111", fg="#bbb", font=("Consolas", 8),
                           state="disabled", wrap="none")
        sb = ttk.Scrollbar(logf, command=self.log.yview)
        self.log.configure(yscrollcommand=sb.set)
        sb.pack(side="right", fill="y")
        self.log.pack(fill="both", expand=True)

        # --- the player: libmpv configured like PlayerService ----------------
        root.update_idletasks()  # realize the frame so winfo_id() is valid
        self.player = mpv.MPV(
            wid=str(self.video.winfo_id()),
            log_handler=self._on_mpv_log,
            loglevel="v",
            # media_kit AndroidVideoController.create sets this so hw decode is
            # attempted for exactly these codecs; only relevant when hwdec != no.
            hwdec_codecs="h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1",
            keep_open="yes",
        )
        # PlayerService.ensureCreated: set once on the long-lived player.
        self.player["hls-bitrate"] = "max"
        self.player["alang"] = "ara,ar"
        self._apply_hwdec()

        root.after(250, self._drain_log)
        root.after(500, self._tick)
        root.protocol("WM_DELETE_WINDOW", self._close)

    # --- actions -----------------------------------------------------------
    def play(self):
        url = self.url_var.get().strip()
        if not url:
            messagebox.showwarning("WCOFlix mpv Player", "Paste a video URL first.")
            return

        # PlayerService._applyHwdec runs BEFORE open — libmpv picks the decoder
        # at file load.
        self._apply_hwdec()
        # media_kit passes EVERY header of Media(httpHeaders:) — including
        # User-Agent — as "Key: Value" entries of http-header-fields (see
        # NativePlayer, media_kit real.dart). Mirror that exactly.
        fields = []
        ua = self.ua_var.get().strip()
        ref = self.ref_var.get().strip()
        if ua:
            fields.append(f"User-Agent: {ua}")
        if ref:
            fields.append(f"Referer: {ref}")
        self.player["http-header-fields"] = fields

        self._log_line(f"--- open {url[:120]}")
        self._log_line(f"--- hwdec={_hwdec_value(self.hwdec_var.get())} headers={fields}")
        self.player.play(url)
        self.player.pause = False
        self.pp_btn.config(text="Pause")

    def _apply_hwdec(self, live: bool = False):
        value = _hwdec_value(self.hwdec_var.get())
        # Property (not option) access: settable during playback, which makes
        # libmpv re-select the decoder immediately.
        self.player.hwdec = value
        if live:
            self._log_line(f"--- hwdec switched LIVE to '{value}'")

    def toggle_pause(self):
        self.player.pause = not self.player.pause
        self.pp_btn.config(text="Play" if self.player.pause else "Pause")

    def stop(self):
        try:
            self.player.command("stop")
        except mpv.ShutdownError:
            return
        self.pp_btn.config(text="Play")
        self.status.config(text="Stopped")

    def skip(self, seconds: int):
        try:
            self.player.command("seek", seconds, "relative")
        except Exception:
            pass  # not seekable yet

    def _on_volume(self, v):
        try:
            self.player.volume = int(float(v))
        except Exception:
            pass

    def _on_seek_release(self, _e):
        self._dragging_seek = False
        try:
            dur = self.player.duration
            if dur:
                self.player.command("seek", dur * self.seek.get() / 1000, "absolute")
        except Exception:
            pass

    # --- mpv log routing (called from mpv's thread — queue to the tk thread) --
    _LOG_PREFIXES = ("vd", "vo", "hwdec", "ffmpeg")

    def _on_mpv_log(self, level, prefix, text):
        interesting = (
            level in ("fatal", "error", "warn")
            or prefix.split("/")[0] in self._LOG_PREFIXES
            or "hwdec" in text
        )
        if interesting:
            self._log_q.put(f"[{level:5}] {prefix}: {text.rstrip()}")

    def _log_line(self, line: str):
        self._log_q.put(line)

    def _drain_log(self):
        wrote = False
        try:
            while True:
                line = self._log_q.get_nowait()
                if not wrote:
                    self.log.configure(state="normal")
                    wrote = True
                self.log.insert("end", line + "\n")
        except queue.Empty:
            pass
        if wrote:
            # Cap the buffer so hours of verbose logs can't bloat the widget.
            n = int(self.log.index("end-1c").split(".")[0])
            if n > 600:
                self.log.delete("1.0", f"{n - 600}.0")
            self.log.see("end")
            self.log.configure(state="disabled")
        self.root.after(250, self._drain_log)

    # --- clock / decode status ------------------------------------------------
    @staticmethod
    def _fmt(s) -> str:
        if s is None:
            return "--:--"
        s = int(s)
        return f"{s // 3600}:{s % 3600 // 60:02}:{s % 60:02}" if s >= 3600 else f"{s // 60}:{s % 60:02}"

    def _tick(self):
        try:
            t, dur = self.player.time_pos, self.player.duration
            self.time_lbl.config(text=f"{self._fmt(t)} / {self._fmt(dur)}")
            if not self._dragging_seek and t and dur:
                self.seek.set(t * 1000 / dur)
            # What actually decoded the frames on screen right now. Attribute
            # access reads mpv PROPERTIES (item access would read options —
            # hwdec-current only exists as a property).
            hw = self.player.hwdec_current
            codec = self.player.video_format
            p = self.player.video_params or {}
            if codec:
                self.status.config(text=(
                    f"decoder: hwdec-current={hw}   codec={codec}   "
                    f"{p.get('w')}x{p.get('h')} {p.get('pixelformat')}   "
                    f"matrix={p.get('colormatrix')} levels={p.get('colorlevels')} "
                    f"primaries={p.get('primaries')}"
                ))
        except (mpv.ShutdownError, RuntimeError):
            return
        except Exception:
            pass  # properties unavailable while idle/loading
        self.root.after(500, self._tick)

    def _close(self):
        try:
            self.player.terminate()
        except Exception:
            pass
        self.root.destroy()


if __name__ == "__main__":
    tk_root = tk.Tk()
    PlayerUI(tk_root, sys.argv[1] if len(sys.argv) > 1 else "")
    tk_root.mainloop()

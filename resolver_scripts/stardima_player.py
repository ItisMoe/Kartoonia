#!/usr/bin/env python3
"""
stardima_player.py  —  in-app HLS player for the Stardima resolver.

Given an *embed page* URL from a host like hgplaycdn / streamhg / lulustream /
uqload (the kind the resolver's `servers()` returns), this module:

  1. EXTRACTS the real video stream (master.m3u8, or an .mp4 fallback) from the
     embed page — including pages where the URL is hidden inside a
     `p,a,c,k,e,d` packed JavaScript block.
  2. PARSES the HLS master manifest to find an Arabic alternative-audio track
     (LANGUAGE="ar" or NAME like "العربية", e.g. index-a2.m3u8).
  3. PLAYS it in a native python-vlc window, injecting the Referer / User-Agent
     headers straight into the video engine so the CDN doesn't blank the stream,
     and FORCING the Arabic audio rendition over the video layer.

Why feed VLC the *master* and force the audio track (instead of hand-building a
manifest that hard-binds index-v1-a1 video + index-a2 audio)?  The sub-playlist
URIs are relative and carry signed `?t=…` tokens; letting VLC resolve them and
then selecting the Arabic rendition gives the exact same result — Arabic audio
over the index-v1 video — without breaking on token/relative-path issues.

----------------------------------------------------------------------------
DEPENDENCIES (pip):
    pip install python-vlc requests
Plus the native VLC media player must be installed (the LibVLC it ships with):
    https://www.videolan.org/vlc/   (use the 64-bit build with 64-bit Python)
----------------------------------------------------------------------------

Use standalone (handy for testing one link):
    python stardima_player.py https://hgplaycdn.com/e/pmm3gqqlyjbv

Or from the GUI:
    import stardima_player
    stardima_player.open_player(root, embed_url, label="Streamhg")
"""

import re
import sys
import threading
import tkinter as tk
from tkinter import ttk
from urllib.parse import urlparse

import requests

try:
    import vlc
except Exception as _e:  # pragma: no cover - import guard
    vlc = None
    _VLC_IMPORT_ERROR = _e

# Headers the CDN expects.  Without a matching Referer the host hands back an
# empty / blank stream, so these are injected on BOTH the scrape requests and
# (later) the VLC playback engine.
DEFAULT_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
              "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")


# --------------------------------------------------------------------------- #
# 1) STREAM EXTRACTION
# --------------------------------------------------------------------------- #
def _origin(url):
    """https://hgplaycdn.com/e/abc  ->  https://hgplaycdn.com/  (used as Referer)."""
    p = urlparse(url)
    return f"{p.scheme}://{p.netloc}/" if p.scheme and p.netloc else url


def _unpack_packed(src):
    """Decode a Dean-Edwards `eval(function(p,a,c,k,e,d){...})` packed block.

    These hosts hide the stream URL inside such a block; we rebuild the original
    source so a plain regex can find the .m3u8 / .mp4.  Returns "" if no packer.
    """
    out = []
    digits = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for m in re.finditer(
            r"\}\('(.*?)',(\d+),(\d+),'(.*?)'\.split\('\|'\)", src, re.DOTALL):
        payload, base, count, words = (
            m.group(1), int(m.group(2)), int(m.group(3)), m.group(4).split("|"))

        def enc(n):
            if n == 0:
                return "0"
            s = ""
            while n > 0:
                s = digits[n % base] + s
                n //= base
            return s

        table = {enc(i): (words[i] if i < len(words) and words[i] else enc(i))
                 for i in range(count)}
        out.append(re.sub(r"\b\w+\b",
                          lambda mo: table.get(mo.group(0), mo.group(0)), payload))
    return "\n".join(out)


# .m3u8 / .mp4 anywhere in text (handles escaped \/ slashes too).
_URL_RE = re.compile(r"https?:\\?/\\?/[^\s\"'\\)\]]+?\.(?:m3u8|mp4)[^\s\"'\\)\]]*")


def extract_stream(embed_url, referer=None, user_agent=DEFAULT_UA, timeout=20):
    """Scrape an embed page and return the playable stream.

    Returns dict:
        { "stream_url", "type" ("hls"|"mp4"), "referer", "user_agent",
          "embed_url" }
    Raises RuntimeError if nothing playable is found.
    """
    referer = referer or _origin(embed_url)
    headers = {"User-Agent": user_agent, "Referer": referer,
               "Accept": "*/*", "Accept-Language": "ar,en;q=0.9"}
    html = requests.get(embed_url, headers=headers, timeout=timeout).text

    # Search the raw page AND any unpacked packer blocks.
    haystacks = [html]
    packed = _unpack_packed(html)
    if packed:
        haystacks.append(packed)

    found = []
    for hay in haystacks:
        for u in _URL_RE.findall(hay):
            found.append(u.replace("\\/", "/"))

    if not found:
        raise RuntimeError("No .m3u8 or .mp4 stream found in the embed page "
                           "(layout may have changed, or it needs a real browser).")

    # Prefer a master HLS playlist, then any HLS, then mp4.
    def rank(u):
        lu = u.lower()
        if "master.m3u8" in lu:
            return 0
        if ".m3u8" in lu:
            return 1
        return 2

    stream = sorted(dict.fromkeys(found), key=rank)[0]
    return {
        "stream_url": stream,
        "type": "hls" if ".m3u8" in stream.lower() else "mp4",
        "referer": referer,
        "user_agent": user_agent,
        "embed_url": embed_url,
    }


# --------------------------------------------------------------------------- #
# 2) MANIFEST PARSING  (find the Arabic audio rendition)
# --------------------------------------------------------------------------- #
def _attrs(line):
    """Parse `#EXT-X-MEDIA:KEY=VAL,KEY="VAL",...` into a dict."""
    out = {}
    for k, v in re.findall(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)', line):
        out[k] = v.strip('"')
    return out


def audio_tracks(master_url, referer, user_agent=DEFAULT_UA, timeout=20):
    """Return [{name, language, uri, is_arabic, default}] for a master.m3u8.

    Empty list if it's not a master playlist (single-stream / mp4).
    """
    headers = {"User-Agent": user_agent, "Referer": referer}
    try:
        text = requests.get(master_url, headers=headers, timeout=timeout).text
    except Exception:
        return []
    tracks = []
    for line in text.splitlines():
        if line.startswith("#EXT-X-MEDIA") and "TYPE=AUDIO" in line:
            a = _attrs(line)
            name = a.get("NAME", "")
            lang = a.get("LANGUAGE", "")
            is_ar = (lang.lower() in ("ar", "ara", "arabic")
                     or "عرب" in name or "العربية" in name)
            tracks.append({
                "name": name,
                "language": lang,
                "uri": a.get("URI", ""),
                "default": a.get("DEFAULT", "").upper() == "YES",
                "is_arabic": is_ar,
            })
    return tracks


def find_arabic(tracks):
    """First Arabic track from audio_tracks(), or None."""
    return next((t for t in tracks if t["is_arabic"]), None)


# --------------------------------------------------------------------------- #
# 3) PLAYER UI  (python-vlc embedded in a Tk window)
# --------------------------------------------------------------------------- #
class PlayerWindow(tk.Toplevel):
    """A self-contained VLC player window with header injection + Arabic audio."""

    def __init__(self, master, embed_url, label="", referer=None,
                 user_agent=DEFAULT_UA):
        super().__init__(master)
        self.embed_url = embed_url
        self.label = label
        self.referer = referer
        self.user_agent = user_agent
        self._arabic_done = False
        self._arabic_name = None  # NAME from the manifest, to match VLC's track

        self.title(f"▶ Player — {label or embed_url}")
        self.geometry("960x600")
        self.minsize(640, 420)
        self.configure(bg="black")

        # --- video surface ---
        self.video_panel = tk.Frame(self, bg="black")
        self.video_panel.pack(fill="both", expand=True)

        # --- control bar ---
        bar = ttk.Frame(self)
        bar.pack(fill="x")
        self.play_btn = ttk.Button(bar, text="⏸ Pause", width=10,
                                   command=self.toggle_pause)
        self.play_btn.pack(side="left", padx=4, pady=4)
        ttk.Button(bar, text="⏹ Stop", width=8,
                   command=self.stop).pack(side="left", padx=2)

        ttk.Label(bar, text="Audio:").pack(side="left", padx=(12, 2))
        self.audio_var = tk.StringVar(value="—")
        self.audio_box = ttk.Combobox(bar, textvariable=self.audio_var,
                                      state="readonly", width=22, values=[])
        self.audio_box.pack(side="left")
        self.audio_box.bind("<<ComboboxSelected>>", self._on_audio_pick)

        self.status = tk.StringVar(value="extracting stream…")
        ttk.Label(bar, textvariable=self.status).pack(side="left", padx=10)

        self.protocol("WM_DELETE_WINDOW", self.on_close)

        if vlc is None:
            self.status.set(f"python-vlc not available: {_VLC_IMPORT_ERROR}")
            return

        # Build the LibVLC instance.  Header options also go on the media below;
        # giving the UA here covers redirect hops the CDN may issue.
        self.instance = vlc.Instance([
            "--quiet",
            "--no-video-title-show",
            f"--http-user-agent={user_agent}",
            "--audio-language=ar,ara,arabic",  # prefer Arabic rendition
        ])
        self.player = self.instance.media_player_new()
        self._bind_video_surface()

        # The worker thread does ONLY network/parse work (Tkinter and VLC player
        # calls must stay on the main thread).  It drops its result here and a
        # main-thread `after` poll picks it up.
        self._prep = None        # dict from extract_stream + arabic info
        self._prep_error = None
        threading.Thread(target=self._extract_worker, daemon=True).start()
        self.after(120, self._poll_prepare)

    # -- embed VLC's output into our Tk frame (Windows: HWND) --
    def _bind_video_surface(self):
        self.update_idletasks()
        handle = self.video_panel.winfo_id()
        if sys.platform.startswith("win"):
            self.player.set_hwnd(handle)
        elif sys.platform == "darwin":
            self.player.set_nsobject(handle)
        else:
            self.player.set_xwindow(handle)

    def _extract_worker(self):
        """Runs OFF the main thread: scrape the stream + parse Arabic audio.

        Only pure network/parse work here — no Tk or VLC player calls.
        """
        try:
            info = extract_stream(self.embed_url, self.referer, self.user_agent)
            ar = None
            if info["type"] == "hls":
                tracks = audio_tracks(info["stream_url"], info["referer"],
                                      self.user_agent)
                ar = find_arabic(tracks)
            info["arabic"] = ar
            self._prep = info
        except Exception as e:
            self._prep_error = str(e)

    def _poll_prepare(self):
        """Main-thread: wait for the worker, then build media + start playback."""
        if self._prep_error is not None:
            self.status.set(f"✗ {self._prep_error}")
            return
        if self._prep is None:
            self.after(120, self._poll_prepare)
            return

        info = self._prep
        self.referer = info["referer"]
        ar = info["arabic"]
        if ar:
            self._arabic_name = ar["name"]

        # Build the media WITH header injection so the CDN serves real bytes.
        media = self.instance.media_new(info["stream_url"])
        media.add_option(f":http-referrer={self.referer}")
        media.add_option(f":http-user-agent={self.user_agent}")
        media.add_option(":network-caching=2000")
        if ar:
            # Bind the Arabic rendition over the index-v1 video layer.
            media.add_option(":audio-language=ar,ara,arabic")

        self.player.set_media(media)
        self.player.play()
        msg = f"playing {info['type'].upper()}"
        msg += "  •  Arabic audio" if ar else "  •  default audio"
        self.status.set(msg)
        # VLC needs a moment to parse renditions before tracks appear.
        self.after(1200, self._refresh_audio_tracks)

    # -- populate the audio-track dropdown and force Arabic once available --
    def _refresh_audio_tracks(self, _tries=0):
        if vlc is None or not self.player.is_playing() and _tries < 12:
            # still buffering; try again shortly
            self.after(700, lambda: self._refresh_audio_tracks(_tries + 1))
            return
        descs = self.player.audio_get_track_description() or []
        names = []
        self._track_ids = {}
        for tid, name in descs:
            if tid == -1:  # the "Disable" pseudo-track
                continue
            label = name.decode("utf-8", "replace") if isinstance(name, bytes) else str(name)
            names.append(label)
            self._track_ids[label] = tid
        if names:
            self.audio_box.configure(values=names)

        # Force the Arabic track exactly once.
        if not self._arabic_done and names:
            target = self._pick_arabic_label(names)
            if target is not None:
                self.player.audio_set_track(self._track_ids[target])
                self.audio_var.set(target)
                self._arabic_done = True
                self.status.set("playing  •  Arabic audio forced")
            else:
                # show whatever is current
                cur = self.player.audio_get_track()
                for lbl, tid in self._track_ids.items():
                    if tid == cur:
                        self.audio_var.set(lbl)
                        break
        # keep the list fresh for a bit (renditions can load late)
        if _tries < 8:
            self.after(1500, lambda: self._refresh_audio_tracks(_tries + 1))

    def _pick_arabic_label(self, names):
        """Match VLC's track label to the Arabic rendition."""
        # First try the exact NAME we read from the manifest ("العربية").
        if self._arabic_name:
            for n in names:
                if self._arabic_name in n:
                    return n
        # Fallback: language heuristics on the label text.
        for n in names:
            low = n.lower()
            if "عرب" in n or "arab" in low or re.search(r"\[ar(a|abic)?\]", low) \
                    or re.search(r"\bar\b", low):
                return n
        return None

    # -- controls --
    def _on_audio_pick(self, _evt=None):
        lbl = self.audio_var.get()
        tid = getattr(self, "_track_ids", {}).get(lbl)
        if tid is not None:
            self.player.audio_set_track(tid)
            self._arabic_done = True  # user override wins from here on

    def toggle_pause(self):
        if vlc is None:
            return
        self.player.pause()  # VLC pause() toggles
        playing = self.player.is_playing()
        self.play_btn.configure(text="⏸ Pause" if playing else "▶ Play")

    def stop(self):
        if vlc is not None:
            self.player.stop()
        self.status.set("stopped")
        self.play_btn.configure(text="▶ Play")

    def on_close(self):
        try:
            if vlc is not None:
                self.player.stop()
                self.player.release()
        except Exception:
            pass
        self.destroy()


def open_player(root, embed_url, label="", referer=None, user_agent=DEFAULT_UA):
    """Convenience entry point used by the GUI: open a player for one link."""
    return PlayerWindow(root, embed_url, label=label,
                        referer=referer, user_agent=user_agent)


# --------------------------------------------------------------------------- #
# Standalone test:  python stardima_player.py <embed_or_stream_url>
# --------------------------------------------------------------------------- #
def main():
    if len(sys.argv) < 2:
        print("usage: python stardima_player.py <embed_url>")
        print("example: python stardima_player.py https://hgplaycdn.com/e/pmm3gqqlyjbv")
        return
    url = sys.argv[1]
    root = tk.Tk()
    root.withdraw()  # we only want the player window
    win = open_player(root, url, label="standalone")
    win.protocol("WM_DELETE_WINDOW", lambda: (win.on_close(), root.destroy()))
    root.mainloop()


if __name__ == "__main__":
    main()

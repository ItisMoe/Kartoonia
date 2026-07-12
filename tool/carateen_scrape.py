#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Carateen catalog scraper  →  assets/carateen_catalog.json (+ carateen_music.json)

carateen.tv is a Vue SPA whose API responses are AES-256-CBC encrypted. We do
NOT need a browser: every endpoint is plain HTTP + a single static key.

  Crypto : AES-256-CBC / PKCS7,  key = "7annaba3l_loves_crypto_safe_key!"
           iv = hex(payload.iv),  ciphertext = hex(payload.encryptedData)
  Header : X-Cartoony-Client: web-frontend-v1   (required)

Pipeline
  /api/tvshows                              -> 336 shows (id,name,cover,desc,…)
  /api/episodes?id=<show>                   -> episodes (id,title,video_id,…)
  play_url  = https://carateen.tv/watch/<show>/<episode>
              (the app's carateen_resolver decrypts /api/episode at playback)
  /music    -> 141 static theme songs bundled in the JS data chunk

Output schema mirrors stardima_catalog.json so the Flutter CarateenAdapter
parses it with the same normalized Show/Movie model.

Run headless :  python tool/carateen_scrape.py --headless
Run with GUI :  python tool/carateen_scrape.py
"""
import os, re, sys, json, time, binascii, threading, argparse
import urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    from Crypto.Cipher import AES
    from Crypto.Util.Padding import unpad
except ImportError:
    sys.stderr.write("pip install pycryptodome\n"); raise

KEY   = b"7annaba3l_loves_crypto_safe_key!"       # 32 bytes -> AES-256
BASE  = "https://carateen.tv"
UA    = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
         "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
HDRS  = {"User-Agent": UA, "X-Cartoony-Client": "web-frontend-v1",
         "Accept": "application/json", "Referer": BASE + "/"}
ROOT  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_CATALOG = os.path.join(ROOT, "assets", "carateen_catalog.json")
OUT_MUSIC   = os.path.join(ROOT, "assets", "carateen_music.json")


# ---------------------------------------------------------------- HTTP + crypto
def _raw(path, tries=4):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(BASE + path, headers=HDRS)
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode("utf-8")
        except Exception as e:                      # noqa: BLE001
            last = e; time.sleep(0.6 * (i + 1))
    raise last


def _decrypt(payload):
    if not (isinstance(payload, dict) and "encryptedData" in payload and "iv" in payload):
        return payload
    iv = binascii.unhexlify(payload["iv"])
    ct = binascii.unhexlify(payload["encryptedData"])
    pt = unpad(AES.new(KEY, AES.MODE_CBC, iv).decrypt(ct), AES.block_size)
    return json.loads(pt.decode("utf-8"))


def api(path):
    return _decrypt(json.loads(_raw(path)))


# --------------------------------------------------------------- normalization
_TAG = re.compile(r"<[^>]+>")
_WS  = re.compile(r"\s+")


def _clean(html):
    if not html:
        return ""
    t = _TAG.sub(" ", str(html)).replace("&nbsp;", " ").replace("&amp;", "&")
    return _WS.sub(" ", t).strip()


IMG = BASE + "/assets/img"


def _poster(show):
    c = show.get("poster_cover") or show.get("poster_cover_alt") or show.get("poster_banner")
    return f"{IMG}/posters/{c}" if c else ""


def _year(show):
    y = str(show.get("release_year") or "").strip()
    m = re.search(r"\d{4}", y)
    return int(m.group(0)) if m else None


def _is_movie(show, ep_count):
    cat = show.get("category") or ""
    return ep_count <= 1 and ("فيلم" in cat or "movie" in cat.lower())


def _episode(show_id, e):
    eid = e.get("id")
    thumb = e.get("thumbnail")
    return {
        "number": (e.get("order_id") or 0),
        "title": e.get("title") or "",
        # the app's carateen_resolver decrypts /api/episode from these ids:
        "play_url": f"{BASE}/watch/{show_id}/{eid}",
        "video_id": str(e.get("video_id") or ""),
        "thumbnail": f"{IMG}/thumbnails/{thumb}" if thumb else "",
        "hls": bool(e.get("hls_supported", True)),
    }


def build_item(show, episodes):
    """Return (kind, dict): 'movie' for single-episode films, else 'show'."""
    sid = show["id"]
    eps = [_episode(sid, e) for e in
           sorted(episodes, key=lambda x: (x.get("order_id", 0), x.get("id", 0)))]
    base = {
        "id": str(sid),
        "title": show.get("title") or "",
        "poster_url": _poster(show),
        "description": _clean(show.get("description")),
        "category": show.get("category") or "",
        "year": _year(show),
        "views": show.get("views"),
        "rating": show.get("rating"),
        "quality": show.get("quality") or "",
    }
    if _is_movie(show, len(eps)) and eps:
        base["play_url"] = eps[0]["play_url"]
        return "movie", base
    base["seasons"] = [{"number": 1, "title": "", "episodes": eps}]
    return "show", base


# -------------------------------------------------------------------- music
def _extract_tracks(js):
    """Pull track object literals out of DEOBFUSCATED JS. Each is:
    {id:…,track:N,title:"…",artist:"…",album:"…",duration:N,
     file:"/assets/music/…mp3",cover:"/…jpg"}"""
    tracks = []
    for m in re.finditer(r'\{[^{}]*?file:\s*"(/assets/music/[^"]+\.mp3)"[^{}]*?\}', js):
        blob = m.group(0)
        def g(k):
            mm = re.search(k + r'\s*:\s*"((?:[^"\\]|\\.)*)"', blob)
            return json.loads('"' + mm.group(1) + '"') if mm else None
        def gi(k):
            mm = re.search(k + r'\s*:\s*(\d+)', blob)
            return int(mm.group(1)) if mm else None
        tracks.append({
            "track": gi("track"),
            "title": g("title") or "",
            "artist": g("artist") or "",
            "album": g("album") or "نوستالجيا",
            "duration": gi("duration") or 0,
            "url": BASE + m.group(1),
            "cover": BASE + (g("cover") or ""),
        })
    tracks.sort(key=lambda t: t["track"] or 0)
    return tracks


def scrape_music(log=lambda *_: None):
    """Refresh the theme-song album from the live JS. Track titles/artists are
    string-array-encoded in the raw bundle, so we deobfuscate the data chunk
    with `npx webcrack` first. If webcrack (node) isn't available, returns []
    and the caller keeps the bundled carateen_music.json."""
    import shutil, tempfile, subprocess
    log("music: locating data chunk…")
    entry_m = re.search(r'/assets/(index-[A-Za-z0-9_-]+\.js)', _raw_text("/"))
    if not entry_m:
        log("music: no entry chunk"); return []
    entry = _raw_text("/assets/" + entry_m.group(1))
    chunks = sorted(set(re.findall(r'([A-Za-z0-9_-]+-[A-Za-z0-9_-]{8}\.js)', entry)))
    data_name = None
    for name in chunks:
        try:
            body = _raw_text("/assets/" + name)
        except Exception:
            continue
        if "nostalgia" in body and "/assets/music/" in body:
            data_name = name; data_raw = body; break
    else:
        log("music: data chunk not found"); return []

    # Try the raw chunk first (mp3 paths are plain even when titles aren't).
    tracks = _extract_tracks(data_raw)
    if tracks and tracks[0]["title"]:
        log(f"music: {len(tracks)} theme songs (raw)"); return tracks

    if not shutil.which("npx"):
        log("music: npx/webcrack unavailable — keeping bundled album"); return []
    try:
        with tempfile.TemporaryDirectory() as td:
            src = os.path.join(td, data_name)
            open(src, "w", encoding="utf-8").write(data_raw)
            subprocess.run(["npx", "--yes", "webcrack", src, "-o", os.path.join(td, "out")],
                           cwd=td, timeout=300, capture_output=True, shell=(os.name == "nt"))
            dec = os.path.join(td, "out", "deobfuscated.js")
            if os.path.exists(dec):
                tracks = _extract_tracks(open(dec, encoding="utf-8").read())
    except Exception as e:                          # noqa: BLE001
        log(f"music: webcrack failed ({e}) — keeping bundled album"); return []
    log(f"music: {len(tracks)} theme songs (deobfuscated)")
    return tracks


def _raw_text(path, tries=3):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(BASE + path,
                                         headers={"User-Agent": UA, "Referer": BASE + "/"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:                      # noqa: BLE001
            last = e; time.sleep(0.5 * (i + 1))
    raise last


# -------------------------------------------------------------------- scrape
def run(progress=lambda done, total, msg="": None, log=lambda *_: None,
        stop=lambda: False, workers=8):
    """Full scrape. `progress(done,total,msg)` + `log(msg)` drive any UI;
    `stop()` lets a UI cancel. Returns (catalog_dict, music_list)."""
    t0 = time.time()
    log("fetching show list  /api/tvshows …")
    shows = api("/api/tvshows")
    total = len(shows)
    log(f"{total} shows")
    progress(0, total, "shows")

    results = [None] * total
    idx = {s["id"]: i for i, s in enumerate(shows)}
    done = 0

    def fetch(show):
        if stop():
            return show["id"], None
        eps = api(f"/api/episodes?id={show['id']}")
        return show["id"], build_item(show, eps if isinstance(eps, list) else [])

    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(fetch, s) for s in shows]
        for fut in as_completed(futs):
            if stop():
                break
            sid, built = fut.result()
            if built is not None:
                results[idx[sid]] = built
            done += 1
            if done % 5 == 0 or done == total:
                title = built[1]["title"] if built else ""
                progress(done, total, title)
                log(f"[{done}/{total}] {title or '(skip)'}")

    tvshows = [r[1] for r in results if r and r[0] == "show"]
    movies = [r[1] for r in results if r and r[0] == "movie"]
    n_eps = sum(len(s["seasons"][0]["episodes"]) for s in tvshows)
    log(f"catalog: {len(tvshows)} shows / {n_eps} episodes / {len(movies)} movies")

    music = scrape_music(log)

    catalog = {
        "source": "carateen",
        "generated_at": int(time.time()),
        "tvshows": tvshows,
        "movies": movies,
        "music": music,
    }
    log(f"done in {time.time()-t0:.0f}s")
    return catalog, music


def save(catalog, music):
    os.makedirs(os.path.dirname(OUT_CATALOG), exist_ok=True)
    with open(OUT_CATALOG, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, separators=(",", ":"))
    # Never overwrite a good album with an empty scrape (webcrack unavailable).
    if music:
        with open(OUT_MUSIC, "w", encoding="utf-8") as f:
            json.dump({"albums": [{"id": "nostalgia", "title": "نوستالجيا",
                                   "tracks": music}]}, f,
                      ensure_ascii=False, separators=(",", ":"))
    return os.path.getsize(OUT_CATALOG)


# -------------------------------------------------------------------- GUI
def gui():
    import tkinter as tk
    from tkinter import ttk, scrolledtext

    root = tk.Tk()
    root.title("Carateen Scraper")
    root.configure(bg="#0F1430")
    root.geometry("640x460")

    tk.Label(root, text="كراتين  ·  Carateen catalog scraper", bg="#0F1430",
             fg="#8fd3ff", font=("Segoe UI", 14, "bold")).pack(pady=(14, 4))
    sub = tk.Label(root, text="pure HTTP + AES · no browser needed", bg="#0F1430",
                   fg="#5b6690", font=("Segoe UI", 9))
    sub.pack()

    bar = ttk.Progressbar(root, length=580, mode="determinate")
    bar.pack(pady=(16, 4))
    stat = tk.Label(root, text="idle", bg="#0F1430", fg="#c9d3ff",
                    font=("Consolas", 10))
    stat.pack()

    box = scrolledtext.ScrolledText(root, width=84, height=15, bg="#070a1c",
                                    fg="#9fb0e6", font=("Consolas", 8),
                                    insertbackground="#fff", borderwidth=0)
    box.pack(padx=14, pady=10, fill="both", expand=True)

    state = {"stop": False, "running": False}

    def log(msg):
        box.insert("end", str(msg) + "\n"); box.see("end")

    def progress(done, total, msg=""):
        bar["maximum"] = total; bar["value"] = done
        stat.config(text=f"{done}/{total}   {msg[:48]}")

    def worker():
        try:
            catalog, music = run(
                progress=lambda d, t, m="": root.after(0, progress, d, t, m),
                log=lambda m: root.after(0, log, m),
                stop=lambda: state["stop"])
            size = save(catalog, music)
            root.after(0, log, f"\nSAVED  {OUT_CATALOG}  ({size/1e6:.1f} MB)")
            root.after(0, log, f"SAVED  {OUT_MUSIC}  ({len(music)} songs)")
            root.after(0, stat.config, {"text": "complete ✓"})
        except Exception as e:                      # noqa: BLE001
            root.after(0, log, f"\nERROR: {e}")
            root.after(0, stat.config, {"text": "error ✗"})
        finally:
            state["running"] = False
            root.after(0, btn.config, {"text": "Scrape", "state": "normal"})

    def toggle():
        if state["running"]:
            state["stop"] = True; log("stopping…"); return
        state["stop"] = False; state["running"] = True
        btn.config(text="Stop"); box.delete("1.0", "end")
        threading.Thread(target=worker, daemon=True).start()

    btn = tk.Button(root, text="Scrape", command=toggle, bg="#2547ff", fg="white",
                    font=("Segoe UI", 11, "bold"), width=16, relief="flat",
                    activebackground="#1a34c0", cursor="hand2")
    btn.pack(pady=(0, 12))
    root.mainloop()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--headless", action="store_true")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()
    if args.headless:
        cat, mus = run(
            progress=lambda d, t, m="": print(f"\r{d}/{t} {m[:40]:<40}", end="", flush=True),
            log=lambda m: print("\n" + str(m)) if not str(m).startswith("[") else None,
            workers=args.workers)
        sz = save(cat, mus)
        print(f"\nSAVED {OUT_CATALOG} ({sz/1e6:.1f} MB), {OUT_MUSIC} ({len(mus)} songs)")
    else:
        gui()

#!/usr/bin/env python3
"""
Stardima on-demand resolver (SKETCH / test harness).

Resolves Stardima video servers in REAL TIME instead of pre-scraping them, so
nothing bloats your catalog and links are always fresh.

How Stardima works (discovered by inspection, June 2026)
--------------------------------------------------------
1. /search?q=<title>            (XHR) -> {"videos":[{id,title,url,poster_url,...}]}
2. show page  /tvshow/video-<id>      -> seasons listed as data-season-id="..".
3. /series/season/<seasonId>    (XHR) -> {"episodes":[{id,episode_number,title,watch_url}]}
      watch_url = https://hyperwatching.com/iframe/<code>
4. The hyperwatching iframe holds a JS config with:
      servers: [{id,name}]  (Lulustream, Uqload, Krakenfiles, Streamhg, Earnvids, Goodstream)
      routes.link = /api/videos/<code>/link   csrf = "..."
   POST link {server_link_id:<id>} (X-CSRF-TOKEN) -> {watch_url:<embed url for that host>}

So per episode we can return MULTIPLE server embed URLs.

This file is BOTH:
  * an importable module (search / seasons / episodes / servers / resolve), and
  * a tiny local web server with a test page:  python stardima_resolver.py
    then open  http://localhost:8765/

In your real app this same logic becomes a backend endpoint
  GET /api/resolve?title=...&season=1&ep=1
that your player calls when the user clicks "Watch".
"""

import os
import re
import json
import time
import html
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, quote
from difflib import SequenceMatcher

import requests

STAR = "https://www.stardima.com"
HW = "https://hyperwatching.com"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

S = requests.Session()
S.headers.update({"User-Agent": UA, "Accept-Language": "ar,en;q=0.9"})

# ---- tiny TTL cache (so repeated plays don't re-hit Stardima) ----
_CACHE = {}
_LOCK = threading.Lock()


def _cached(key, ttl, fn):
    now = time.time()
    with _LOCK:
        v = _CACHE.get(key)
        if v and now - v[0] < ttl:
            return v[1]
    r = fn()
    with _LOCK:
        _CACHE[key] = (now, r)
    return r


# --------------------------------------------------------------------------- #
# Stardima API
# --------------------------------------------------------------------------- #
def search(title):
    def f():
        r = S.get(f"{STAR}/search", params={"q": title},
                  headers={"X-Requested-With": "XMLHttpRequest"}, timeout=20)
        return r.json().get("videos", [])
    return _cached(("search", title), 600, f)


def _norm(s):
    return re.sub(r"\s+", " ", (s or "")).strip().lower()


def best_match(title, vids):
    best, bs = None, 0.0
    for v in vids:
        sc = SequenceMatcher(None, _norm(title), _norm(v.get("title", ""))).ratio()
        if sc > bs:
            bs, best = sc, v
    return best, round(bs, 3)


def _play_url(show_url):
    """The show page exposes only its default episode via og:video; that 'play'
    page is where the full season list lives."""
    h = S.get(show_url, timeout=20).text
    m = re.search(r'og:video"\s+content="([^"]+)"', h)
    return m.group(1) if m else None


INDEX_FILE = "stardima_index.json"
_INDEX = None


def build_index(log=print):
    """Crawl the full series listing (/mosalsalat) once -> stardima_index.json.
    This gives accurate title->show matching (the site search is too broad)."""
    out = []
    first = S.get(f"{STAR}/mosalsalat", params={"page": 1},
                  headers={"X-Requested-With": "XMLHttpRequest"}, timeout=20).json()
    last = first.get("pagination", {}).get("last_page", 1)
    log(f"series listing: {last} pages")

    def absorb(vids):
        for v in vids:
            out.append({"id": v.get("id"), "title": v.get("title"),
                        "url": v.get("url"), "poster_url": v.get("poster_url")})
    absorb(first.get("videos", []))
    for p in range(2, last + 1):
        try:
            d = S.get(f"{STAR}/mosalsalat", params={"page": p},
                      headers={"X-Requested-With": "XMLHttpRequest"},
                      timeout=20).json()
            absorb(d.get("videos", []))
        except Exception as e:
            log(f"  page {p} error: {e}")
        if p % 15 == 0:
            log(f"  page {p}/{last}  ({len(out)} series)")
        time.sleep(0.15)
    with open(INDEX_FILE, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    log(f"index built: {len(out)} series -> {INDEX_FILE}")
    global _INDEX
    _INDEX = out
    return out


def load_index():
    global _INDEX
    if _INDEX is None:
        _INDEX = (json.load(open(INDEX_FILE, encoding="utf-8"))
                  if os.path.exists(INDEX_FILE) else [])
    return _INDEX


def match_index(title):
    best, bs = None, 0.0
    for v in load_index():
        sc = SequenceMatcher(None, _norm(title), _norm(v.get("title", ""))).ratio()
        if sc > bs:
            bs, best = sc, v
    return best, round(bs, 3)


def seasons(show_url):
    def f():
        pu = _play_url(show_url)
        if not pu:
            return []
        h = S.get(pu, timeout=20, headers={"Referer": show_url}).text
        pairs = re.findall(
            r'data-season-id="(\d+)"\s+data-season-number="([^"]*)"', h)
        return [{"season_id": sid, "season_number": num} for sid, num in pairs]
    return _cached(("seasons", show_url), 600, f)


def episodes(season_id):
    def f():
        r = S.get(f"{STAR}/series/season/{season_id}",
                  headers={"X-Requested-With": "XMLHttpRequest"}, timeout=20)
        return r.json().get("episodes", [])
    return _cached(("eps", season_id), 300, f)


def servers(watch_url):
    """Resolve a hyperwatching iframe URL into a list of {server, embed_url}."""
    m = re.search(r"/iframe/([^/?#]+)", watch_url or "")
    if not m:
        return []
    code = m.group(1)
    iframe = f"{HW}/iframe/{code}"
    h = S.get(iframe, headers={"Referer": STAR + "/"}, timeout=20).text
    cm = re.search(r'csrf:\s*"([^"]+)"', h)
    if not cm:
        return []
    csrf = cm.group(1)
    srv = re.findall(r'id:\s*"(\d+)",\s*name:\s*"([^"]+)"', h)
    hdr = {"Content-Type": "application/json", "X-CSRF-TOKEN": csrf,
           "X-Requested-With": "XMLHttpRequest", "Referer": iframe, "Origin": HW}
    out = []
    for sid, sname in srv:
        try:
            j = S.post(f"{HW}/api/videos/{code}/link", headers=hdr,
                       json={"server_link_id": sid}, timeout=20).json()
            if j.get("watch_url"):
                out.append({"server": sname, "embed_url": j["watch_url"]})
        except Exception:
            pass
    return out


def resolve(title, season_number=None, episode_number=1):
    """Full chain: title -> best Stardima show -> season -> episode -> servers."""
    # 1) match against the local index (accurate); 2) fall back to site search
    show, conf = match_index(title)
    source = "index"
    if not show or conf < 0.6:
        vids = search(title)
        s2, c2 = best_match(title, vids)
        if s2 and c2 > conf:
            show, conf, source = s2, c2, "search"
    if not show:
        return {"error": "no show match", "query": title,
                "hint": "build the index first: /api/build-index"}
    ssn = seasons(show["url"])
    sid = None
    if ssn:
        if season_number is not None:
            for s in ssn:
                if str(season_number) in (s["season_number"] or ""):
                    sid = s["season_id"]
                    break
        sid = sid or ssn[0]["season_id"]
    eps = episodes(sid) if sid else []
    ep = None
    if episode_number is not None:
        for e in eps:
            if e.get("episode_number") == int(episode_number):
                ep = e
                break
    ep = ep or (eps[0] if eps else None)
    if not ep:
        return {"error": "no episode found", "show": show["title"],
                "confidence": conf, "seasons": ssn}
    srv = servers(ep.get("watch_url", ""))
    return {
        "query": title,
        "matched_show": show["title"],
        "match_source": source,
        "show_url": show["url"],
        "match_confidence": conf,
        "poster_url": show.get("poster_url"),
        "season_id": sid,
        "available_seasons": ssn,
        "episode": {"number": ep.get("episode_number"),
                    "title": ep.get("title")},
        "hyperwatching_iframe": ep.get("watch_url"),   # the all-in-one player
        "servers": srv,                                # individual host embeds
    }


# --------------------------------------------------------------------------- #
# Local test web server
# --------------------------------------------------------------------------- #
TEST_PAGE = """<!doctype html><html lang="ar" dir="rtl"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Stardima Resolver — test</title>
<style>
 body{font-family:Segoe UI,Arial;background:#0f1115;color:#e8e8e8;margin:0;padding:20px}
 h1{font-size:18px} input,button{font-size:15px;padding:8px;border-radius:8px;border:1px solid #333}
 input{background:#1b1f27;color:#fff} button{background:#2563eb;color:#fff;cursor:pointer;border:0}
 .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:12px}
 .srv{display:inline-block;margin:4px;padding:8px 12px;background:#1b1f27;border:1px solid #2a2f3a;border-radius:8px;cursor:pointer}
 .srv:hover{border-color:#2563eb}
 iframe{width:100%;height:62vh;border:0;border-radius:10px;background:#000;margin-top:10px}
 a{color:#6ea8fe} #info{font-size:13px;color:#9aa4b2;margin:6px 0}
 small{color:#6b7280}
</style></head><body>
<h1>Stardima Resolver — live test</h1>
<div class="row">
 <input id="t" placeholder="اسم المسلسل / show title" size="28" value="المحقق كونان">
 <input id="s" placeholder="season" size="6" value="1">
 <input id="e" placeholder="episode" size="6" value="1">
 <button onclick="go()">Resolve ▶</button>
</div>
<div id="info"></div>
<div id="servers"></div>
<iframe id="player" allowfullscreen
 allow="autoplay; fullscreen; encrypted-media; picture-in-picture"></iframe>
<script>
async function go(){
  const t=document.getElementById('t').value,
        s=document.getElementById('s').value,
        e=document.getElementById('e').value;
  document.getElementById('info').textContent='resolving…';
  document.getElementById('servers').innerHTML='';
  const r=await fetch(`/api/resolve?title=${encodeURIComponent(t)}&season=${s}&ep=${e}`);
  const d=await r.json();
  if(d.error){document.getElementById('info').textContent='⚠ '+d.error;return;}
  document.getElementById('info').innerHTML=
    `matched: <b>${d.matched_show}</b> (conf ${d.match_confidence}) — `+
    `ep ${d.episode.number}: ${d.episode.title||''} `+
    `<small>[${(d.available_seasons||[]).length} seasons]</small>`;
  const box=document.getElementById('servers');
  // all-in-one hyperwatching player first (most reliable in an iframe)
  add(box,'⭐ Player (all servers)', d.hyperwatching_iframe);
  (d.servers||[]).forEach(x=>add(box,x.server,x.embed_url));
  if(d.hyperwatching_iframe) load(d.hyperwatching_iframe);
}
function add(box,name,url){
  if(!url)return;
  const b=document.createElement('span');b.className='srv';
  b.innerHTML=name+' <a href="'+url+'" target="_blank" title="open in new tab">↗</a>';
  b.onclick=()=>load(url);
  box.appendChild(b);
}
function load(url){document.getElementById('player').src=url;}
</script>
<p><small>Note: some third-party hosts block being embedded in an iframe — if a
server shows blank, use the ↗ link to open it in a new tab. The ⭐ player always
embeds.</small></p>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        b = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        try:
            if u.path == "/":
                return self._send(200, TEST_PAGE, "text/html")
            if u.path == "/api/search":
                return self._send(200, json.dumps(
                    search(q.get("q", [""])[0]), ensure_ascii=False))
            if u.path == "/api/build-index":
                idx = build_index()
                return self._send(200, json.dumps(
                    {"ok": True, "series": len(idx)}, ensure_ascii=False))
            if u.path == "/api/resolve":
                d = resolve(q.get("title", [""])[0],
                            q.get("season", [None])[0],
                            q.get("ep", ["1"])[0])
                return self._send(200, json.dumps(d, ensure_ascii=False))
            return self._send(404, json.dumps({"error": "not found"}))
        except Exception as e:
            return self._send(500, json.dumps({"error": str(e)}))

    def log_message(self, *a):
        pass  # quiet


def main(port=8765):
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Stardima resolver running →  http://localhost:{port}/")
    print("API:  /api/resolve?title=...&season=1&ep=1   |   /api/search?q=...")
    print("Ctrl+C to stop.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped.")


if __name__ == "__main__":
    main()

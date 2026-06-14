#!/usr/bin/env python3
"""
Stardima server resolver (SIMPLE).

Input  : a Stardima *play* URL for one episode, e.g.
         https://www.stardima.com/tvshow/video-309/play/15628
Output : the real per-server embed links you can drop into your player,
         e.g. [{"server": "Lulustream", "embed_url": "https://..."}].

The hyperwatching iframe URL is NEVER returned (it's a player page, not a
video link) — it's only used internally to ask each host for its embed URL.

Flow
----
1. GET the play page -> find the hyperwatching iframe code embedded in it.
2. GET the hyperwatching iframe -> read its csrf token + server list.
3. For each server: POST /api/videos/<code>/link -> {watch_url: <embed>}.

Use it two ways:
  * CLI : python stardima_resolver.py "https://www.stardima.com/tvshow/video-309/play/15628"
  * Web : python stardima_resolver.py        (opens a tiny test page on :8765)
  * Import: from stardima_resolver import resolve; resolve(play_url)
"""

import re
import json
import html
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import requests

STAR = "https://www.stardima.com"
HW = "https://hyperwatching.com"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

S = requests.Session()
S.headers.update({"User-Agent": UA, "Accept-Language": "ar,en;q=0.9"})


# --------------------------------------------------------------------------- #
# 1) play page  ->  hyperwatching iframe code
# --------------------------------------------------------------------------- #
def _hyperwatching_code(play_url):
    """Return the hyperwatching <code> embedded in a Stardima play page."""
    h = S.get(play_url, headers={"Referer": STAR + "/"}, timeout=20).text

    # The play page embeds the player for this exact episode; the iframe URL
    # may appear as an iframe src, inside JSON, or in an og:video meta tag.
    patterns = [
        r'https?://(?:www\.)?hyperwatching\.com/iframe/([A-Za-z0-9_\-]+)',
        r'"watch_url"\s*:\s*"[^"]*?/iframe/([A-Za-z0-9_\-]+)"',
        r'og:video"\s+content="[^"]*?/iframe/([A-Za-z0-9_\-]+)"',
    ]
    for p in patterns:
        m = re.search(p, html.unescape(h))
        if m:
            return m.group(1)
    return None


# --------------------------------------------------------------------------- #
# 2 + 3) iframe code  ->  per-server embed links
# --------------------------------------------------------------------------- #
def servers_for_code(code):
    """Ask hyperwatching for every host's embed URL. Returns [{server,embed_url}]."""
    iframe = f"{HW}/iframe/{code}"
    h = S.get(iframe, headers={"Referer": STAR + "/"}, timeout=20).text

    cm = re.search(r'csrf:\s*"([^"]+)"', h)
    if not cm:
        return []
    csrf = cm.group(1)

    # server list, e.g.  id:"3", name:"Lulustream"
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


# --------------------------------------------------------------------------- #
# public entry point
# --------------------------------------------------------------------------- #
def resolve(play_url):
    """play_url -> {"play_url", "servers": [{server, embed_url}, ...]}."""
    code = _hyperwatching_code(play_url)
    if not code:
        return {"error": "no hyperwatching iframe found on play page",
                "play_url": play_url}
    srv = servers_for_code(code)
    if not srv:
        return {"error": "iframe found but no servers resolved",
                "play_url": play_url, "code": code}
    return {"play_url": play_url, "servers": srv}


# --------------------------------------------------------------------------- #
# tiny local test web server (optional)
# --------------------------------------------------------------------------- #
TEST_PAGE = """<!doctype html><html lang="ar" dir="rtl"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Stardima Resolver — test</title>
<style>
 body{font-family:Segoe UI,Arial;background:#0f1115;color:#e8e8e8;margin:0;padding:20px}
 h1{font-size:18px} input,button{font-size:15px;padding:8px;border-radius:8px;border:1px solid #333}
 input{background:#1b1f27;color:#fff;flex:1;min-width:280px} button{background:#2563eb;color:#fff;cursor:pointer;border:0}
 .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:12px}
 .srv{display:inline-block;margin:4px;padding:8px 12px;background:#1b1f27;border:1px solid #2a2f3a;border-radius:8px;cursor:pointer}
 .srv:hover{border-color:#2563eb}
 iframe{width:100%;height:62vh;border:0;border-radius:10px;background:#000;margin-top:10px}
 a{color:#6ea8fe} #info{font-size:13px;color:#9aa4b2;margin:6px 0}
 small{color:#6b7280}
</style></head><body>
<h1>Stardima Resolver — paste a play URL</h1>
<div class="row">
 <input id="u" placeholder="https://www.stardima.com/tvshow/video-309/play/15628"
        value="https://www.stardima.com/tvshow/video-309/play/15628">
 <button onclick="go()">Resolve ▶</button>
</div>
<div id="info"></div>
<div id="servers"></div>
<iframe id="player" allowfullscreen
 allow="autoplay; fullscreen; encrypted-media; picture-in-picture"></iframe>
<script>
async function go(){
  const u=document.getElementById('u').value;
  document.getElementById('info').textContent='resolving…';
  document.getElementById('servers').innerHTML='';
  document.getElementById('player').src='about:blank';
  const r=await fetch(`/api/resolve?play_url=${encodeURIComponent(u)}`);
  const d=await r.json();
  if(d.error){document.getElementById('info').textContent='⚠ '+d.error;return;}
  document.getElementById('info').innerHTML=`found <b>${d.servers.length}</b> server(s)`;
  const box=document.getElementById('servers');
  d.servers.forEach((x,i)=>{
    const b=document.createElement('span');b.className='srv';
    b.innerHTML=x.server+' <a href="'+x.embed_url+'" target="_blank" title="open in new tab">↗</a>';
    b.onclick=()=>{document.getElementById('player').src=x.embed_url;};
    box.appendChild(b);
    if(i===0)document.getElementById('player').src=x.embed_url;
  });
}
</script>
<p><small>Some hosts block being embedded in an iframe — if a server shows blank,
use the ↗ link to open it in a new tab.</small></p>
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
            if u.path == "/api/resolve":
                d = resolve(q.get("play_url", [""])[0])
                return self._send(200, json.dumps(d, ensure_ascii=False))
            return self._send(404, json.dumps({"error": "not found"}))
        except Exception as e:
            return self._send(500, json.dumps({"error": str(e)}))

    def log_message(self, *a):
        pass  # quiet


def main(port=8765):
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Stardima resolver running →  http://localhost:{port}/")
    print("API:  /api/resolve?play_url=https://www.stardima.com/tvshow/video-309/play/15628")
    print("Ctrl+C to stop.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped.")


if __name__ == "__main__":
    # If a play URL is passed on the command line, just resolve and print JSON.
    if len(sys.argv) > 1 and sys.argv[1].startswith("http"):
        print(json.dumps(resolve(sys.argv[1]), ensure_ascii=False, indent=2))
    else:
        main()
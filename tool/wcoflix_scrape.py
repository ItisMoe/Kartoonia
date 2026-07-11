"""Re-scrape the wcoflix snapshot from live wcoflix.tv (ports tool/wcoflix_scrape.dart
+ lib/services/wcoflix/wcoflix_parsers.dart, which can no longer run under `dart run`
because wcoflix_domain now imports Flutter) and drop catalog titles that are not on
wcoflix.tv. Writes both assets IN PLACE (Windows locks assets/*.json against replace)."""
import json
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

BASE = "https://www.wcoflix.tv"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36")

RE_ANCHOR = re.compile(r'<a href="([^"]+)"[^>]*>(.*?)</a>', re.S)
RE_DDMCC = re.compile(r'<li(?:\s+data-id="[0-9]+")?>\s*<a href="([^"]+)"[^>]*>(.*?)</a>', re.S)
RE_RECENT = re.compile(
    r'<div class="img">\s*<a href="([^"]+)">\s*<img[^>]*src="([^"]+)"[^>]*>\s*</a>\s*</div>'
    r'\s*<div class="recent-release-episodes"><a href="[^"]*"[^>]*>([^<]+)</a>', re.S)
RE_TAG = re.compile(r"<[^>]*>")
RE_WS = re.compile(r"\s+")

UNESCAPES = [("&amp;", "&"), ("&#038;", "&"), ("&#039;", "'"), ("&#39;", "'"),
             ("&#8217;", "’"), ("&#8216;", "‘"), ("&#8211;", "–"),
             ("&#8230;", "…"), ("&quot;", '"')]


def unescape(s):
    for a, b in UNESCAPES:
        s = s.replace(a, b)
    return s


def text(inner):
    return unescape(RE_WS.sub(" ", RE_TAG.sub(" ", inner)).strip())


def block(html, anchor, end):
    start = html.find(anchor)
    if start == -1:
        return ""
    stop = html.find(end, start)
    return html[start:] if stop == -1 else html[start:stop]


def parse_sidebar_titles(html):
    return [(m.group(1), text(m.group(2)), None)
            for m in RE_ANCHOR.finditer(block(html, 'class="sidebar-titles"', "</ul>"))]


def parse_ddmcc(html):
    return [(m.group(1), text(m.group(2)), None)
            for m in RE_DDMCC.finditer(block(html, 'class="ddmcc"', "<script"))
            if not m.group(1).startswith("#")]


def parse_recent(html):
    out = []
    for m in RE_RECENT.finditer(html):
        thumb = m.group(2) if m.group(2).startswith("http") else "https:" + m.group(2)
        out.append((m.group(1), unescape(m.group(3).strip()), thumb))
    return out


ROUTES = {
    "popular": ("/", parse_sidebar_titles),
    "latest": ("/last-50-recent-release", parse_recent),
    "cartoons": ("/cartoon-list", parse_ddmcc),
    "dubbed": ("/dubbed-anime-list", parse_ddmcc),
    "movies": ("/movie-list", parse_ddmcc),
    "ova": ("/ova-list", parse_ddmcc),
}


def to_path(url):
    if not url.startswith("http"):
        return url if url.startswith("/") else "/" + url
    m = re.match(r"https?://[^/]+(/[^?#]*)(\?[^#]*)?", url)
    return (m.group(1) + (m.group(2) or "")) if m else url


def fetch(path):
    req = urllib.request.Request(BASE + path, headers={
        "User-Agent": UA, "Referer": BASE + "/", "Accept-Language": "en-US,en;q=0.9"})
    with urllib.request.urlopen(req, timeout=30) as r:
        if r.status != 200:
            raise RuntimeError(f"HTTP {r.status} for {path}")
        return r.read().decode("utf-8", "replace")


def scrape_route(key):
    path, parse = ROUTES[key]
    links = parse(fetch(path))
    seen, items = set(), []
    for href, title, thumb in links:
        p = to_path(href)
        if not title.strip() or p in seen:
            continue
        seen.add(p)
        item = {"u": p, "t": title.strip()}
        if thumb:
            item["th"] = thumb
        items.append(item)
    print(f"  {key}: {len(items)} items")
    return key, items


def main():
    print("live mirror:", BASE)
    with ThreadPoolExecutor(6) as ex:
        snapshot = dict(ex.map(scrape_route, ROUTES))
    total = sum(len(v) for v in snapshot.values())
    if total < 1000:
        print(f"ABORT: only {total} items scraped - assets left unchanged.")
        sys.exit(1)

    live_paths = {e["u"] for lst in snapshot.values() for e in lst}
    print(f"scraped {total} entries, {len(live_paths)} unique paths")

    with open("assets/wcoflix_snapshot.json", "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False, separators=(",", ":"))

    cat = json.load(open("assets/wcoflix_catalog.json", encoding="utf-8"))
    before = len(cat["items"])
    cat["items"] = {k: v for k, v in cat["items"].items() if k in live_paths}
    cat["total"] = len(cat["items"])
    with open("assets/wcoflix_catalog.json", "w", encoding="utf-8") as f:
        json.dump(cat, f, ensure_ascii=False, separators=(",", ":"))
    print(f"catalog: kept {cat['total']} of {before} "
          f"(removed {before - cat['total']} titles not on wcoflix.tv)")


if __name__ == "__main__":
    main()

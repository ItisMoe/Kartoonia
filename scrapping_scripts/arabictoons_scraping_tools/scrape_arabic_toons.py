#!/usr/bin/env python3
"""
Production scraper for arabic-toons.com

Builds arabic_toons_catalog.json containing every show (with episodes + video
server links) and every movie (with video server links).

Key facts discovered by live inspection of the site (June 2026):

* Catalog pages:  /cartoon.php  and  /movies.php
  - Pagination is offset/page based via  ?next=N  (NOT ?page=N).
  - The total number of pages is in  <div class="pagination-numbers" data-total="N">.
  - Each card is an  <a href="{slug}-{id}-anime-streaming.html" title="ARABIC TITLE">
    (or  ...-movies-streaming.html)  with an  <img src=".../cat_{id}.jpg">.

* Show detail page ({slug}-{id}-anime-streaming.html):
  - Description in  <div id="descriptionText">.
  - Rating shown in  <span id="score">3.48</span>  (fallback: var scoreValue).
  - Episodes in  <div class="episodes-grid">  as
    <a href="{slug}-{id}-{episode_id}.html#sets">
       <div class="episode-item" data-episode-id="..." data-series-id="...">
         <div class="episode-number">N</div>
         <div class="cinema-title">الحلقة N</div>

* Episode / movie watch page:
  - The video URL lives in a <script> as  const videoSrc = "https://....mp4?tkn=...";
  - The on-page "المشغل 1/2/3" buttons are three *player UIs* (Clappr / Plyr /
    native) for the SAME source, not three different servers. So each episode /
    movie has a single real stream URL. We still emit it as a servers[] list
    (server_number 1) to match the requested schema, and keep both the clean
    base URL and the raw tokenized URL.

The page bytes are UTF-8 but the server omits a charset, so we force r.encoding.
"""

import requests
from bs4 import BeautifulSoup
import re
import json
import time
import logging
import os
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse, urlunparse

# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #
BASE_URL = "https://www.arabic-toons.com"
HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"),
    "Accept-Language": "ar,en;q=0.9",
    "Referer": BASE_URL + "/",
}
SLEEP = float(os.environ.get("SCRAPE_SLEEP", "1.2"))   # seconds between requests
TEST_LIMIT = int(os.environ.get("SCRAPE_TEST", "0"))   # >0 = only N shows + N movies
# When SCRAPE_PRIORITY=1, only scrape shows whose id is listed in PRIORITY_FILE
# (a curated allowlist of well-known classic Spacetoon/Disney/CN Arabic-dubbed
# shows). Movies are always scraped in full.
PRIORITY = os.environ.get("SCRAPE_PRIORITY", "0") == "1"
PRIORITY_FILE = "priority_shows.json"
CHECKPOINT_FILE = "progress.json"
OUTPUT_FILE = "arabic_toons_catalog.json"
ERROR_LOG = "scraper_errors.log"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(ERROR_LOG, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("arabic-toons")

# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #
def get_session():
    s = requests.Session()
    s.headers.update(HEADERS)
    return s


def fetch(session, url, retries=3):
    """GET a URL with retries / backoff. Returns decoded text or None."""
    for attempt in range(1, retries + 1):
        try:
            r = session.get(url, timeout=20)
            if r.status_code == 200:
                r.encoding = "utf-8"          # server sends no charset; bytes are UTF-8
                return r.text
            if r.status_code == 404:
                log.warning(f"404 {url} -> skip")
                return None
            if r.status_code == 429:
                log.warning(f"429 rate limited {url}; sleeping 60s")
                time.sleep(60)
                continue
            log.warning(f"HTTP {r.status_code} {url} (attempt {attempt})")
        except Exception as e:
            log.error(f"request error {url}: {e} (attempt {attempt})")
        time.sleep(2 ** attempt)
    log.error(f"giving up on {url}")
    return None


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
def strip_query(url):
    """Drop query string + fragment, keep scheme/host/path (the stable base URL)."""
    p = urlparse(url.strip())
    return urlunparse((p.scheme, p.netloc, p.path, "", "", ""))


def extract_video_servers(html):
    """
    Return list of {server_number, url, raw_url} for every distinct stream URL
    found on an episode/movie page.

    Order of strategies:
      1. const/var/let videoSrc = "...";          (current site format)
      2. var serverN = "...";                      (legacy multi-server format)
      3. <source>/<video src="...">                (embedded player tags)
      4. any bare .mp4/.m3u8/.mkv URL in the HTML  (last-resort fallback)
    """
    raws = []

    # 1. videoSrc
    raws += re.findall(r'(?:const|let|var)\s+videoSrc\s*=\s*["\']([^"\']+)["\']',
                       html, re.IGNORECASE)

    # 2. legacy var serverN  (keep server number from the var name)
    legacy = re.findall(r'var\s+server(\d+)\s*=\s*["\']([^"\']{10,})["\']',
                        html, re.IGNORECASE)

    # 3. <source>/<video src>
    if not raws and not legacy:
        try:
            soup = BeautifulSoup(html, "lxml")
            for tag in soup.find_all(["source", "video"], src=True):
                raws.append(tag.get("src", ""))
        except Exception:
            pass

    # 4. bare media URLs
    if not raws and not legacy:
        raws += re.findall(r'https?://[^"\'<>\s]+\.(?:mp4|m3u8|mkv)[^"\'<>\s]*', html)

    servers = []
    seen = set()

    def add(raw, forced_number=None):
        raw = (raw or "").strip()
        if not raw.startswith("http"):
            return
        # The site appends  + "&_=" + Date.now()  outside the string, so the
        # captured value already ends cleanly at the quote. Still strip stray
        # trailing concatenation artifacts just in case.
        raw = raw.split('"')[0].split("'")[0].strip()
        clean = strip_query(raw)
        # require a real filename with extension in the path
        last = clean.rsplit("/", 1)[-1]
        if "." not in last:
            return
        if clean in seen:
            return
        seen.add(clean)
        servers.append({
            "server_number": forced_number if forced_number else len(servers) + 1,
            "url": clean,
            "raw_url": raw,
        })

    for raw in raws:
        add(raw)
    for num, raw in legacy:
        add(raw, forced_number=int(num))

    # renumber sequentially to be safe/consistent
    for i, s in enumerate(servers, 1):
        s["server_number"] = i
    return servers


def extract_rating(html):
    """Precise displayed rating from #score span; fallback to var scoreValue."""
    m = re.search(r'id="score"[^>]*>\s*([0-9]+\.[0-9]+)', html)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            pass
    m = re.search(r'scoreValue\s*=\s*([0-9]+(?:\.[0-9]+)?)', html)
    if m:
        try:
            v = float(m.group(1))
            return v if v > 0 else None
        except ValueError:
            pass
    return None


def extract_description(soup):
    el = soup.find(id="descriptionText")
    if el:
        return el.get_text(strip=True)
    el = soup.find("div", class_=re.compile(r"description-text", re.I))
    return el.get_text(strip=True) if el else ""


_CARD_RE = re.compile(
    r'([a-z0-9_\-]+)-(\d+)-(anime|movies)-streaming\.html', re.IGNORECASE)


def parse_catalog_items(html, want_type):
    """
    Parse a catalog listing page. want_type in {"show","movie"}.
    Returns list of metadata dicts (deduped by id, order preserved).
    """
    soup = BeautifulSoup(html, "lxml")
    items = []
    seen = set()
    target = "anime" if want_type == "show" else "movies"
    for a in soup.find_all("a", href=True):
        href = a["href"]
        m = _CARD_RE.search(href)
        if not m:
            continue
        slug, item_id, kind = m.group(1), m.group(2), m.group(3).lower()
        if kind != target:
            continue
        if item_id in seen:
            continue
        seen.add(item_id)
        full_url = href if href.startswith("http") else f"{BASE_URL}/{href.lstrip('/')}"
        full_url = full_url.split("#")[0]
        # title: prefer the <a title="..."> attribute, else cinema-title text
        title = (a.get("title") or "").strip()
        if not title:
            ct = a.find(class_=re.compile(r"cinema-title", re.I))
            title = ct.get_text(strip=True) if ct else slug
        items.append({
            "id": item_id,
            "slug": slug,
            "title": title,
            "type": want_type,
            "thumbnail_url": f"{BASE_URL}/images/anime/cat_{item_id}.jpg",
            "page_url": full_url,
        })
    return items


def get_total_pages(html):
    m = re.search(r'data-total="(\d+)"', html)
    return int(m.group(1)) if m else 1


def scrape_catalog(session, php_page, want_type):
    """Iterate every catalog page and return a deduped list of item metadata."""
    first_url = f"{BASE_URL}/{php_page}"
    first_html = fetch(session, first_url)
    if not first_html:
        log.error(f"could not load first catalog page {first_url}")
        return []
    total_pages = get_total_pages(first_html)
    log.info(f"{php_page}: {total_pages} pages")

    all_items = []
    seen = set()

    def absorb(items):
        for it in items:
            if it["id"] not in seen:
                seen.add(it["id"])
                all_items.append(it)

    absorb(parse_catalog_items(first_html, want_type))

    for page in range(2, total_pages + 1):
        url = f"{BASE_URL}/{php_page}?next={page}"
        log.info(f"catalog {php_page} page {page}/{total_pages}")
        html = fetch(session, url)
        if not html:
            continue
        before = len(all_items)
        absorb(parse_catalog_items(html, want_type))
        if len(all_items) == before:
            log.info(f"  page {page} added no new items")
        time.sleep(SLEEP)

    log.info(f"{php_page}: collected {len(all_items)} unique {want_type}s")
    return all_items


def parse_episodes(soup, show_title):
    """Return ordered, deduped list of episode dicts from a show detail page."""
    episodes = []
    seen = set()
    grid = soup.find("div", class_=re.compile(r"episodes-grid", re.I))
    scope = grid if grid else soup
    for a in scope.find_all("a", href=True):
        item = a.find("div", class_=re.compile(r"\bepisode-item\b", re.I))
        if not item:
            continue
        href = a["href"].split("#")[0]
        ep_url = href if href.startswith("http") else f"{BASE_URL}/{href.lstrip('/')}"
        if ep_url in seen:
            continue
        seen.add(ep_url)

        ep_id = item.get("data-episode-id")
        num_el = item.find("div", class_=re.compile(r"episode-number", re.I))
        ep_num = None
        if num_el:
            mm = re.search(r"\d+", num_el.get_text())
            ep_num = int(mm.group()) if mm else None
        ct = item.find("div", class_=re.compile(r"cinema-title", re.I))
        ct_txt = ct.get_text(strip=True) if ct else ""
        if ep_num is None:
            mm = re.search(r"(\d+)", ct_txt) or re.search(r"-(\d+)\.html", href)
            ep_num = int(mm.group(1)) if mm else None
        ep_title = (f"{show_title} {ct_txt}".strip() if ct_txt
                    else (a.get("title") or "").strip())

        episodes.append({
            "episode_number": ep_num,
            "episode_id": ep_id,
            "episode_title": ep_title,
            "episode_url": ep_url,
            "servers": [],
        })
    episodes.sort(key=lambda e: (e["episode_number"] is None, e["episode_number"] or 0))
    return episodes


def scrape_show_detail(session, meta):
    html = fetch(session, meta["page_url"])
    if not html:
        return None
    soup = BeautifulSoup(html, "lxml")
    description = extract_description(soup)
    rating = extract_rating(html)
    episodes = parse_episodes(soup, meta["title"])

    log.info(f"  show '{meta['title']}' -> {len(episodes)} episodes")
    for ep in episodes:
        ep_html = fetch(session, ep["episode_url"])
        if ep_html:
            ep["servers"] = extract_video_servers(ep_html)
            if not ep["servers"]:
                log.warning(f"    no servers for ep {ep['episode_number']} "
                            f"{ep['episode_url']}")
        time.sleep(SLEEP)

    return {
        "id": meta["id"],
        "slug": meta["slug"],
        "title": meta["title"],
        "type": "show",
        "thumbnail_url": meta["thumbnail_url"],
        "description": description,
        "rating": rating,
        "total_episodes": len(episodes),
        "page_url": meta["page_url"],
        "episodes": episodes,
    }


def scrape_movie_detail(session, meta):
    html = fetch(session, meta["page_url"])
    if not html:
        return None
    soup = BeautifulSoup(html, "lxml")
    description = extract_description(soup)
    rating = extract_rating(html)
    servers = extract_video_servers(html)
    if not servers:
        log.warning(f"  no servers for movie {meta['title']} {meta['page_url']}")
    return {
        "id": meta["id"],
        "slug": meta["slug"],
        "title": meta["title"],
        "type": "movie",
        "thumbnail_url": meta["thumbnail_url"],
        "description": description,
        "rating": rating,
        "page_url": meta["page_url"],
        "servers": servers,
    }


# --------------------------------------------------------------------------- #
# Checkpoint
# --------------------------------------------------------------------------- #
def load_checkpoint():
    if os.path.exists(CHECKPOINT_FILE):
        try:
            with open(CHECKPOINT_FILE, "r", encoding="utf-8") as f:
                d = json.load(f)
            d.setdefault("scraped_show_ids", [])
            d.setdefault("scraped_movie_ids", [])
            d.setdefault("shows", [])
            d.setdefault("movies", [])
            return d
        except Exception as e:
            log.error(f"corrupt checkpoint ({e}); starting fresh")
    return {"scraped_show_ids": [], "scraped_movie_ids": [], "shows": [], "movies": []}


def _atomic_write(path, payload):
    """Write JSON atomically, retrying the rename on transient Windows
    'Access is denied' errors (another process briefly reading the file)."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    for attempt in range(1, 8):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.5 * attempt)
    # last resort: leave the .tmp so data is recoverable, and log it
    log.error(f"could not replace {path} after retries; data left in {tmp}")


def save_checkpoint(cp):
    _atomic_write(CHECKPOINT_FILE, cp)


def write_output(shows, movies):
    out = {
        "scraped_at": datetime.now(timezone.utc).isoformat(),
        "total_shows": len(shows),
        "total_movies": len(movies),
        "shows": shows,
        "movies": movies,
    }
    _atomic_write(OUTPUT_FILE, out)


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main():
    session = get_session()
    cp = load_checkpoint()
    scraped_show_ids = set(cp["scraped_show_ids"])
    scraped_movie_ids = set(cp["scraped_movie_ids"])
    shows = cp["shows"]
    movies = cp["movies"]

    if TEST_LIMIT:
        log.info(f"*** TEST MODE: limiting to {TEST_LIMIT} shows + {TEST_LIMIT} movies ***")

    # ----- shows -----
    log.info("=== scraping shows catalog ===")
    show_meta = scrape_catalog(session, "cartoon.php", "show")
    if PRIORITY and os.path.exists(PRIORITY_FILE):
        with open(PRIORITY_FILE, "r", encoding="utf-8") as f:
            pri_ids = {str(x["id"]) for x in json.load(f)}
        before = len(show_meta)
        show_meta = [m for m in show_meta if m["id"] in pri_ids]
        log.info(f"PRIORITY mode: {len(show_meta)} of {before} shows selected "
                 f"({len(pri_ids)} ids in allowlist)")
    if TEST_LIMIT:
        show_meta = show_meta[:TEST_LIMIT]
    for i, meta in enumerate(show_meta, 1):
        if meta["id"] in scraped_show_ids:
            continue
        log.info(f"[show {i}/{len(show_meta)}] {meta['title']} ({meta['id']})")
        data = scrape_show_detail(session, meta)
        if data:
            shows.append(data)
            scraped_show_ids.add(meta["id"])
            cp["scraped_show_ids"] = list(scraped_show_ids)
            cp["shows"] = shows
            save_checkpoint(cp)
            write_output(shows, movies)
        time.sleep(SLEEP)

    # ----- movies -----
    log.info("=== scraping movies catalog ===")
    movie_meta = scrape_catalog(session, "movies.php", "movie")
    if TEST_LIMIT:
        movie_meta = movie_meta[:TEST_LIMIT]
    for i, meta in enumerate(movie_meta, 1):
        if meta["id"] in scraped_movie_ids:
            continue
        log.info(f"[movie {i}/{len(movie_meta)}] {meta['title']} ({meta['id']})")
        data = scrape_movie_detail(session, meta)
        if data:
            movies.append(data)
            scraped_movie_ids.add(meta["id"])
            cp["scraped_movie_ids"] = list(scraped_movie_ids)
            cp["movies"] = movies
            save_checkpoint(cp)
            write_output(shows, movies)
        time.sleep(SLEEP)

    write_output(shows, movies)
    log.info(f"DONE. shows={len(shows)} movies={len(movies)} -> {OUTPUT_FILE}")


if __name__ == "__main__":
    main()

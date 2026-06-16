#!/usr/bin/env python3
"""
Enrich arabic_toons_catalog.json with TMDB data (high-quality posters, overview,
genres, rating, year) WITHOUT touching the existing scraped fields.

For every show / movie it adds a "tmdb" block:

    "tmdb": {
        "tmdb_id": 12345, "type": "tv",
        "title": "Grendizer", "original_title": "UFOロボ グレンダイザー",
        "poster_url": "https://image.tmdb.org/t/p/original/xxx.jpg",
        "poster_url_w500": "https://image.tmdb.org/t/p/w500/xxx.jpg",
        "backdrop_url": "https://image.tmdb.org/t/p/original/yyy.jpg",
        "overview_ar": "...", "overview_en": "...",
        "genres": ["Animation", "Action"],
        "vote_average": 8.1, "year": 1975,
        "match_confidence": 0.93, "match_query": "grendizer"
    }

If nothing matches, "tmdb" is set to null (so the entry is still marked as
processed and won't be retried on resume; the frontend falls back to the
scraped thumbnail_url).

API key
-------
Provide a free TMDB key in any of these ways (checked in order):
  * env var  TMDB_API_KEY   (v3 key)  or  TMDB_TOKEN (v4 read-access token)
  * a file   tmdb_key.txt   containing just the key/token
  * CLI:     python enrich_tmdb.py --key YOUR_KEY
Both the v3 API key and the v4 bearer token are supported (auto-detected).

Resumable: writes the catalog every 25 items; rerun to continue. Entries that
already have a "tmdb" key (even null) are skipped.
"""

import os
import re
import sys
import json
import time
import argparse
import unicodedata
from difflib import SequenceMatcher

import requests

GROUPED = "arabic_toons_grouped.json"
FLAT = "arabic_toons_catalog.json"
IMG = "https://image.tmdb.org/t/p/"


def default_input():
    """Prefer the grouped catalog (series-level) if it exists."""
    return GROUPED if os.path.exists(GROUPED) else FLAT


def needs_enrich(item, force=False):
    """Decide whether an item should be (re)processed.
    * missing 'tmdb'            -> yes
    * old single-language block -> yes (upgrade to bilingual ar/en)
    * bilingual block already   -> only if force
    * null (no match earlier)   -> only if force
    """
    if "tmdb" not in item:
        return True
    t = item["tmdb"]
    if t is None:
        return force
    if isinstance(t, dict) and "ar" not in t:   # old format -> upgrade
        return True
    return force
API = "https://api.themoviedb.org/3"
SLEEP = 0.08
SAVE_EVERY = 25
MIN_CONFIDENCE = 0.50   # below this -> treated as no match

# --------------------------------------------------------------------------- #
# Alias map: Arabic-dub title substring -> English search term, for famous
# classics whose Arabic name does not match TMDB by title/slug.
# --------------------------------------------------------------------------- #
ALIASES = {
    "كابتن ماجد": "Captain Tsubasa",
    "عدنان ولينا": "Future Boy Conan",
    "ابطال الكرة": "Inazuma Eleven",
    "أبطال الكرة": "Inazuma Eleven",
    "ابطال الملاعب": "Inazuma Eleven",
    "ليدي اوسكار": "The Rose of Versailles",
    "ساندي بل": "Hello! Sandybell",
    "ماروكو": "Chibi Maruko-chan",
    "هايدي": "Heidi, Girl of the Alps",
    "ريمي": "Nobody's Boy Remi",
    "سندباد": "Sinbad",
    "زينة ونحول": "The Wonderful Adventures of Nils",
    "سلاحف النينجا": "Teenage Mutant Ninja Turtles",
    "النينجا": "Teenage Mutant Ninja Turtles",
    "النمر الوردي": "Pink Panther",
    "جريندايزر": "UFO Robot Grendizer",
    "مازنجر": "Mazinger",
    "فولترون": "Voltron",
    "جورجي": "Georgie",
    "سالي": "Little Princess Sara",
    "علاء الدين": "Aladdin",
    "السنافر": "The Smurfs",
    "تيمون وبومبا": "Timon and Pumbaa",
    "مغامرات سندباد": "Sinbad",
    "كرة قدم المجرات": "Galactik Football",
    "محقق": "Detective",
    "سبونج بوب": "SpongeBob SquarePants",
    "ابطال السبنجيتسو": "Bakugan",
    "همتارو": "Hamtaro",
    "انيوشا": "Inuyasha",
    "سلام دانك": "Slam Dunk",
}

# season / part / movie noise tokens to strip from Arabic titles
AR_NOISE = re.compile(r"(الموسم|الجزء|الحلقة|الحزء)\b.*$")
AR_MOVIE = re.compile(r"^\s*فيلم\s+")
SLUG_DROP = re.compile(r"^(s\d+|season\d*|part\d*|\d+|aljz|aljza|s|hd|tv)$", re.I)


# --------------------------------------------------------------------------- #
def get_key():
    p = argparse.ArgumentParser()
    p.add_argument("--key", default=None)
    args, _ = p.parse_known_args()
    key = (args.key
           or os.environ.get("TMDB_TOKEN")
           or os.environ.get("TMDB_API_KEY"))
    if not key and os.path.exists("tmdb_key.txt"):
        key = open("tmdb_key.txt", encoding="utf-8").read().strip()
    return key


def make_session(key):
    s = requests.Session()
    s.headers.update({"Accept": "application/json"})
    # v4 read-access tokens are JWTs (three dot-separated base64 parts,
    # usually starting with "eyJ"); use Bearer auth for those.
    is_v4 = key.count(".") == 2 and key.startswith("eyJ")
    if is_v4:
        s.headers["Authorization"] = "Bearer " + key
        s._auth_param = {}
    else:
        s._auth_param = {"api_key": key}
    return s


def api_get(session, path, **params):
    params.update(session._auth_param)
    for attempt in range(1, 4):
        try:
            r = session.get(API + path, params=params, timeout=20)
            if r.status_code == 200:
                return r.json()
            if r.status_code == 401:
                print("ERROR: TMDB rejected the key (401). Check your API key/token.")
                sys.exit(1)
            if r.status_code == 429:
                wait = int(r.headers.get("Retry-After", "2"))
                time.sleep(wait + 1)
                continue
        except Exception as e:
            time.sleep(attempt)
    return None


def fetch_genre_maps(session):
    maps = {}
    for kind in ("tv", "movie"):
        data = api_get(session, f"/genre/{kind}/list", language="en")
        maps[kind] = {g["id"]: g["name"] for g in (data or {}).get("genres", [])}
    return maps


# --------------------------------------------------------------------------- #
def normalize(s):
    s = unicodedata.normalize("NFKC", s or "").lower().strip()
    s = re.sub(r"[ـً-ٟ]", "", s)      # arabic tatweel/diacritics
    s = re.sub(r"[^\w\s؀-ۿ]", " ", s)      # keep word chars + arabic
    s = re.sub(r"\s+", " ", s).strip()
    return s


def clean_arabic_title(title):
    t = AR_MOVIE.sub("", title or "")
    t = AR_NOISE.sub("", t)
    t = re.sub(r"\d+", "", t)
    return t.strip()


def clean_slug(slug):
    parts = re.split(r"[-_]+", slug or "")
    keep = [p for p in parts if p and not SLUG_DROP.match(p)
            and not re.fullmatch(r"[0-9a-f]{16,}", p)]   # drop hash-like slugs
    return " ".join(keep).strip()


def similarity(a, b):
    return SequenceMatcher(None, normalize(a), normalize(b)).ratio()


def alias_for(title):
    for ar, en in ALIASES.items():
        if ar in title:
            return en
    return None


def score_result(query, res):
    names = [res.get("name"), res.get("original_name"),
             res.get("title"), res.get("original_title")]
    best = max((similarity(query, n) for n in names if n), default=0.0)
    return best


def build_queries(item):
    """Ordered list of (query_text, language) to try."""
    title = item.get("title", "")
    slug = item.get("slug", "")
    qs = []
    al = alias_for(title)
    if al:
        qs.append((al, "en"))
    cs = clean_slug(slug)
    if cs:
        qs.append((cs, "en"))
    ca = clean_arabic_title(title)
    if ca:
        qs.append((ca, "ar"))
    # de-dupe preserving order
    seen = set(); out = []
    for q, lang in qs:
        k = (q.lower(), lang)
        if k not in seen:
            seen.add(k); out.append((q, lang))
    return out


def search_best(session, item, kind):
    """kind: 'tv' or 'movie'. Returns (best_result, confidence, query)."""
    best = None; best_score = 0.0; best_q = ""
    for q, lang in build_queries(item):
        data = api_get(session, f"/search/{kind}", query=q, language=lang,
                       include_adult="false")
        time.sleep(SLEEP)
        for res in (data or {}).get("results", [])[:5]:
            sc = score_result(q, res)
            # small popularity tiebreak
            sc += min(res.get("popularity", 0) / 1000.0, 0.05)
            if sc > best_score:
                best_score, best, best_q = sc, res, q
        # strong early match -> stop
        if best_score >= 0.9:
            break
    return best, round(min(best_score, 1.0), 3), best_q


def _url(path, size="original"):
    return (IMG + size + path) if path else None


def _pick_image(images, lang):
    """Best image (by vote) for a given language code; lang=None => no-language
    (language-neutral) artwork."""
    cands = [im for im in images if im.get("iso_639_1") == lang]
    if not cands:
        return None
    cands.sort(key=lambda im: (im.get("vote_average", 0), im.get("vote_count", 0)),
               reverse=True)
    return cands[0].get("file_path")


def fetch_details(session, kind, tmdb_id):
    """Return (ar_details, en_details, images)."""
    ar = api_get(session, f"/{kind}/{tmdb_id}", language="ar") or {}
    time.sleep(SLEEP)
    en = api_get(session, f"/{kind}/{tmdb_id}", language="en") or {}
    time.sleep(SLEEP)
    imgs = api_get(session, f"/{kind}/{tmdb_id}/images",
                   include_image_language="ar,en,null") or {}
    time.sleep(SLEEP)
    return ar, en, imgs


def _lang_block(details, posters, backdrops, lang):
    """Build a per-language sub-block (title/overview/poster/backdrop/genres).
    Prefers artwork in `lang`, then language-neutral, then the details default."""
    poster = (_pick_image(posters, lang)
              or _pick_image(posters, None)
              or details.get("poster_path"))
    backdrop = (_pick_image(backdrops, lang)
                or _pick_image(backdrops, None)
                or details.get("backdrop_path"))
    genres = [g.get("name") for g in details.get("genres", []) if g.get("name")]
    return {
        "title": details.get("name") or details.get("title"),
        "overview": details.get("overview", "") or "",
        "genres": genres,
        "poster_url": _url(poster),
        "poster_url_w500": _url(poster, "w500"),
        "backdrop_url": _url(backdrop),
    }


def build_tmdb_block(session, res, kind, conf, query):
    """Bilingual TMDB block: shared fields + 'ar' and 'en' sub-blocks (each with
    its own localized title/overview/genres/poster/backdrop), plus convenience
    top-level poster/backdrop (language-neutral default)."""
    tid = res["id"]
    ar_d, en_d, imgs = fetch_details(session, kind, tid)
    posters = imgs.get("posters", [])
    backdrops = imgs.get("backdrops", [])

    date = (en_d.get("first_air_date") or en_d.get("release_date")
            or res.get("first_air_date") or res.get("release_date") or "")
    year = int(date[:4]) if date[:4].isdigit() else None

    ar_block = _lang_block(ar_d, posters, backdrops, "ar")
    en_block = _lang_block(en_d, posters, backdrops, "en")
    # if ar overview missing, fall back to the search result's
    if not ar_block["overview"]:
        ar_block["overview"] = res.get("overview", "") or ""

    default_poster = (_pick_image(posters, None) or en_d.get("poster_path")
                      or res.get("poster_path"))
    default_backdrop = (_pick_image(backdrops, None) or en_d.get("backdrop_path")
                        or res.get("backdrop_path"))

    return {
        "tmdb_id": tid,
        "type": kind,
        "original_title": res.get("original_name") or res.get("original_title"),
        "vote_average": en_d.get("vote_average", res.get("vote_average")),
        "vote_count": en_d.get("vote_count", res.get("vote_count")),
        "popularity": en_d.get("popularity", res.get("popularity")),
        "year": year,
        "match_confidence": conf,
        "match_query": query,
        # convenience defaults (language-neutral)
        "poster_url": _url(default_poster),
        "poster_url_w500": _url(default_poster, "w500"),
        "backdrop_url": _url(default_backdrop),
        # full bilingual detail
        "ar": ar_block,
        "en": en_block,
    }


# --------------------------------------------------------------------------- #
def save(cat, path):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cat, f, ensure_ascii=False, indent=2)
    for _ in range(8):
        try:
            os.replace(tmp, path); return
        except PermissionError:
            time.sleep(0.5)


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    p = argparse.ArgumentParser()
    p.add_argument("--key", default=None)
    p.add_argument("--input", default=None)
    p.add_argument("--force", action="store_true",
                   help="re-fetch everything, including already-matched and "
                        "previously-unmatched items")
    args, _ = p.parse_known_args()

    key = get_key()
    if not key:
        print("No TMDB key found. Put it in tmdb_key.txt, set TMDB_API_KEY / "
              "TMDB_TOKEN, or pass --key YOUR_KEY.")
        sys.exit(1)
    session = make_session(key)

    # validate key
    if not api_get(session, "/configuration"):
        print("Could not reach TMDB / key invalid.")
        sys.exit(1)
    print("TMDB key OK.")

    path = args.input or default_input()
    print(f"enriching: {path}")
    cat = json.load(open(path, encoding="utf-8"))
    items = [("tv", s) for s in cat["shows"]] + [("movie", m) for m in cat["movies"]]
    total = len(items)
    todo = [(k, it) for k, it in items if needs_enrich(it, args.force)]
    print(f"{total} items, {total - len(todo)} up-to-date, {len(todo)} to do"
          f"{' (force)' if args.force else ''}.")

    matched = unmatched = 0
    processed = 0
    for kind, item in todo:
        res, conf, q = search_best(session, item, kind)
        if res and conf >= MIN_CONFIDENCE and res.get("poster_path"):
            item["tmdb"] = build_tmdb_block(session, res, kind, conf, q)
            matched += 1
            tag = "OK "
        else:
            item["tmdb"] = None
            unmatched += 1
            tag = "-- "
        processed += 1
        try:
            print(f"[{processed}/{len(todo)}] {tag}conf={conf:.2f}  "
                  f"{item.get('title','')[:40]}")
        except Exception:
            pass
        if processed % SAVE_EVERY == 0:
            save(cat, path)
    save(cat, path)
    print(f"\nDone. matched={matched}  unmatched={unmatched}  "
          f"(catalog updated: {path})")


if __name__ == "__main__":
    main()

"""Existence-verify every wcoflix title page on wcoflix.tv (parallel), then prune
dead titles from assets/wcoflix_snapshot.json and assets/wcoflix_catalog.json.

Alive = HTTP 200, not a Cloudflare challenge, not a redirect to the homepage,
and the page actually carries playable content:
  - series pages: episode anchors (dark-episode-item / sonra / episode hrefs)
    or a player iframe
  - episode/movie pages: the /inc/embed/ player iframe
Transient failures (network, 5xx, challenge after retries) count as ALIVE so a
flaky run can never mass-delete good titles. Assets are rewritten IN PLACE.
"""
import json
import re
import sys
import threading
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor

BASE = "https://www.wcoflix.tv"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36")
WORKERS = 20

RE_EMBED = re.compile(r'<iframe[^>]*\ssrc="[^"]*/inc/embed/')
RE_EPISODE_HREF = re.compile(r'<a[^>]+href="[^"]*episode[^"]*"', re.I)

lock = threading.Lock()
done = 0
dead = {}          # path -> reason
challenged = 0


def is_challenge(body):
    return ("Just a moment" in body or "cf-browser-verification" in body
            or "Attention Required" in body)


def fetch(path):
    req = urllib.request.Request(BASE + path, headers={
        "User-Agent": UA, "Referer": BASE + "/",
        "Accept-Language": "en-US,en;q=0.9"})
    with urllib.request.urlopen(req, timeout=25) as r:
        return r.status, r.geturl(), r.read().decode("utf-8", "replace")


def check(path):
    global done, challenged
    verdict = None  # None = alive
    for attempt in range(3):
        try:
            status, final_url, body = fetch(path)
        except urllib.error.HTTPError as e:
            if e.code in (404, 410):
                verdict = f"http {e.code}"
                break
            time.sleep(2 * (attempt + 1))   # 5xx/429: retry, else keep alive
            continue
        except Exception:
            time.sleep(2 * (attempt + 1))
            continue
        if is_challenge(body):
            with lock:
                challenged += 1
            time.sleep(4 * (attempt + 1))
            continue
        final_path = re.sub(r"^https?://[^/]+", "", final_url) or "/"
        if final_path in ("/", ""):
            verdict = "redirects to home"
            break
        has_embed = bool(RE_EMBED.search(body))
        has_eps = ('dark-episode-item' in body or 'class="cat-eps' in body
                   or RE_EPISODE_HREF.search(body) is not None)
        if not has_embed and not has_eps:
            verdict = "no episodes / no player"
        break
    with lock:
        done += 1
        if verdict:
            dead[path] = verdict
        if done % 500 == 0:
            print(f"  {done} checked, {len(dead)} dead, "
                  f"{challenged} challenges", flush=True)


def main():
    snap = json.load(open("assets/wcoflix_snapshot.json", encoding="utf-8"))
    cat = json.load(open("assets/wcoflix_catalog.json", encoding="utf-8"))
    paths = sorted({e["u"] for lst in snap.values() for e in lst}
                   | set(cat["items"]))
    print(f"verifying {len(paths)} unique title pages on {BASE} "
          f"with {WORKERS} workers", flush=True)
    t0 = time.time()
    with ThreadPoolExecutor(WORKERS) as ex:
        list(ex.map(check, paths))
    print(f"done in {time.time() - t0:.0f}s: {len(dead)} dead of {len(paths)}")

    frac = len(dead) / max(1, len(paths))
    if frac > 0.30:
        print(f"ABORT: {frac:.0%} dead looks like a broken run — no changes.")
        sys.exit(1)

    for reason in sorted(set(dead.values())):
        n = sum(1 for r in dead.values() if r == reason)
        print(f"  dead[{reason}]: {n}")

    for key in snap:
        before = len(snap[key])
        snap[key] = [e for e in snap[key] if e["u"] not in dead]
        if before != len(snap[key]):
            print(f"snapshot[{key}]: {before} -> {len(snap[key])}")
    with open("assets/wcoflix_snapshot.json", "w", encoding="utf-8") as f:
        json.dump(snap, f, ensure_ascii=False, separators=(",", ":"))

    before = len(cat["items"])
    cat["items"] = {k: v for k, v in cat["items"].items() if k not in dead}
    cat["total"] = len(cat["items"])
    with open("assets/wcoflix_catalog.json", "w", encoding="utf-8") as f:
        json.dump(cat, f, ensure_ascii=False, separators=(",", ":"))
    print(f"catalog: {before} -> {cat['total']}")

    with open("dead_titles.txt", "w", encoding="utf-8") as f:
        for p, r in sorted(dead.items()):
            f.write(f"{p}\t{r}\n")
    print("dead list -> dead_titles.txt")


if __name__ == "__main__":
    main()

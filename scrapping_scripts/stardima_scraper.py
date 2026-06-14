#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Stardima catalog scraper  (stardima.com)  -- FAST / PARALLEL edition  (v2)
==========================================================================

Scrapes ONLY the dubbed (language=dub) titles under:
    - https://www.stardima.com/aflam?language=dub          (movies)
    - https://www.stardima.com/mosalsalat?language=dub     (tv shows / series)

WHY v2  (what was actually wrong)
---------------------------------
The play page (e.g. /tvshow/6a2aeb49559d8/play/94016) is a React/Laravel SPA.
The list of episodes is **not** present in the server-rendered HTML — only the
single currently-active episode marker is. The old scraper called
`page.content()` once and parsed it with BeautifulSoup, so it was reading a
half-hydrated DOM:
    * episode hrefs came out as "/tvshow/undefined/play/ID"
    * episode titles were empty or wrong
    * multi-season shows duplicated season 1

v2 fixes this with three independent, merged data sources, in order of trust:

  1. NETWORK CAPTURE (most reliable): a response listener records every JSON
     payload the SPA fetches. When a season tab is clicked the site requests
     that season's episodes as JSON; we parse it directly. Episode play-ids are
     always NUMERIC (94016) while show/recommendation ids are hex hashes
     (6a2aeb...), so we keep only numeric ids and never pick up recommendation
     cards by mistake.

  2. LIVE DOM (fallback): we read the *rendered* DOM via page.evaluate
     (querySelectorAll), not a stale page.content() snapshot, capturing each
     /play/ anchor's href, text, title/aria attributes and its card text.

  3. We merge 1 + 2, dedupe by numeric episode id, prefer entries that carry a
     real title, and rebuild every play_url as
         /tvshow/{show_hid}/play/{episode_id}
     so "undefined" can never appear.

LOGGING
-------
Every show logs its title; every season logs its label, resolved number and
episode count; failures log the captured API urls + a DOM snippet and dump the
raw HTML + captured JSON to a ./debug folder next to the output file so the
exact structure can be inspected.

--------------------------------------------------------------------------------
INSTALL (one time):
    pip install playwright beautifulsoup4
    playwright install chromium
RUN:
    python stardima_scraper_fixed_v2.py
--------------------------------------------------------------------------------
"""

import asyncio
import json
import os
import re
import queue
import sys
import threading
import time
import traceback
from dataclasses import dataclass, field, asdict

# ---- GUI (stdlib) ----
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

# ---- scraping deps ----
try:
    from playwright.async_api import async_playwright, TimeoutError as PWTimeout
except ImportError:
    async_playwright = None
    PWTimeout = Exception

try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None


# ============================================================================
# CONFIG
# ============================================================================
BASE = "https://www.stardima.com"
MOVIES_URL = BASE + "/aflam?language=dub&page={page}"
SHOWS_URL  = BASE + "/mosalsalat?language=dub&page={page}"

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

# NOTE: we no longer block media/xhr indiscriminately; we keep blocking heavy
# *visual* assets only, because the episode JSON travels over fetch/xhr and must
# never be aborted.
BLOCK_RESOURCE_TYPES = {"image", "stylesheet", "font", "media", "imageset"}

SELECTORS = {
    "movie_link_re":   re.compile(r"/movie/([A-Za-z0-9\-]+)"),
    "show_link_re":    re.compile(r"/tvshow/([A-Za-z0-9\-]+)"),
    # capture show-id segment + numeric episode id
    "episode_link_re": re.compile(r"/tvshow/([A-Za-z0-9\-]+)/play/(\d+)"),
    # a play link as it may appear in any href form
    "any_play_re":     re.compile(r"/play/(\d+)\b"),
    "movie_play_re":   re.compile(r"/play/([A-Za-z0-9\-]+)\b"),
    "ignore_sections_text": [
        "مقترحات", "المزيد من هذا", "اكتشف الجديد", "استمتع باختياراتنا"
    ],
    "season_tab_keyword": "الموسم",
}

DEFAULTS = {
    "out_path":       os.path.join(os.getcwd(), "catalog.json"),
    "delay":          0.3,
    "nav_timeout":    45000,
    "headless":       True,
    "max_pages":      0,
    "concurrency":    6,
    "block_resources": True,
    "do_movies":      True,
    "do_shows":       True,
    "save_every":     8,
    "debug_dump":     True,   # dump raw html + json when a show yields 0 episodes
}


# ============================================================================
# DATA MODELS
# ============================================================================
@dataclass
class Episode:
    number: int
    title: str
    play_url: str

@dataclass
class Season:
    number: int
    title: str
    episodes: list = field(default_factory=list)

@dataclass
class Movie:
    id: str; type: str; title: str; description: str; poster_url: str
    backdrop_url: str; year: str; language: str; category: str
    detail_url: str; play_url: str

@dataclass
class TVShow:
    id: str; type: str; title: str; description: str; poster_url: str
    backdrop_url: str; year: str; language: str; category: str
    detail_url: str; seasons: list = field(default_factory=list)


# ============================================================================
# ASYNC SCRAPER ENGINE
# ============================================================================
class StardimaScraper:
    def __init__(self, cfg, msg_queue: "queue.Queue", stop_event: threading.Event):
        self.cfg   = cfg
        self.q     = msg_queue
        self.stop  = stop_event
        self.movies = []
        self.shows  = []
        self._completed = 0
        self._debug_dir = os.path.join(
            os.path.dirname(cfg["out_path"]) or ".", "stardima_debug"
        )

    def log(self, t): self.q.put(("log", t))
    def status(self, t): self.q.put(("status", t))
    def progress(self, kind, done, total): self.q.put(("progress", (kind, done, total)))
    def counts(self): self.q.put(("counts", (len(self.movies), len(self.shows))))

    def _stopped(self): return self.stop.is_set()

    def run(self):
        if async_playwright is None:
            self.q.put(("error",
                "Playwright missing.\n\npip install playwright beautifulsoup4\nplaywright install chromium"))
            self.q.put(("done", None)); return
        if BeautifulSoup is None:
            self.q.put(("error", "beautifulsoup4 missing.\n\npip install beautifulsoup4"))
            self.q.put(("done", None)); return
        try:
            asyncio.run(self._run_async())
        except KeyboardInterrupt:
            self._save()
            self.log("\n=== STOPPED by user (partial results saved) ===")
            self.status("Stopped")
        except Exception as e:
            self.log("\n!!! ERROR:\n" + traceback.format_exc())
            self.q.put(("error", str(e)))
        finally:
            self.q.put(("done", None))

    async def _run_async(self):
        async with async_playwright() as pw:
            browser = await pw.chromium.launch(
                headless=self.cfg["headless"],
                args=["--disable-blink-features=AutomationControlled", "--no-sandbox"],
            )
            ctx = await browser.new_context(
                user_agent=USER_AGENT,
                viewport={"width": 1366, "height": 900},
                locale="ar",
                service_workers="block",
            )
            if self.cfg["block_resources"]:
                await ctx.route("**/*", self._route_block)

            movie_targets, show_targets = [], []
            if self.cfg["do_movies"]:
                self.log("=== Discovering MOVIES ===")
                movie_targets = await self._discover(ctx, "movie")
                self.log(f"=== {len(movie_targets)} movies discovered ===\n")
            if self.cfg["do_shows"]:
                self.log("=== Discovering TV SHOWS ===")
                show_targets = await self._discover(ctx, "show")
                self.log(f"=== {len(show_targets)} shows discovered ===\n")

            sem = asyncio.Semaphore(max(1, int(self.cfg["concurrency"])))

            if movie_targets and not self._stopped():
                self.log(
                    f"=== Scraping {len(movie_targets)} movies "
                    f"(concurrency={self.cfg['concurrency']}) ==="
                )
                await self._scrape_batch(ctx, movie_targets, "movie", sem)
            if show_targets and not self._stopped():
                self.log(
                    f"=== Scraping {len(show_targets)} shows "
                    f"(concurrency={self.cfg['concurrency']}) ==="
                )
                await self._scrape_batch(ctx, show_targets, "show", sem)

            await ctx.close()
            await browser.close()

        self._save()
        self.status("Done")
        self.log("\n=== FINISHED ===")
        self.log(f"Movies: {len(self.movies)} | Shows: {len(self.shows)}")
        self.log(f"Saved to: {self.cfg['out_path']}")

    async def _route_block(self, route):
        try:
            rt = route.request.resource_type
            if rt in BLOCK_RESOURCE_TYPES:
                await route.abort()
            else:
                await route.continue_()
        except Exception:
            try: await route.continue_()
            except Exception: pass

    async def _goto(self, page, url, wait="domcontentloaded"):
        last = None
        for attempt in range(1, 4):
            if self._stopped(): return False
            try:
                await page.goto(url, timeout=self.cfg["nav_timeout"], wait_until=wait)
                try:
                    await page.wait_for_load_state("networkidle", timeout=8000)
                except PWTimeout:
                    pass
                if self.cfg["delay"]:
                    await asyncio.sleep(self.cfg["delay"])
                return True
            except Exception as e:
                last = e
                self.log(f"   ! load failed (try {attempt}/3): {url} [{type(e).__name__}]")
                await asyncio.sleep(1.5 * attempt)
        self.log(f"   !! giving up: {url}: {last}")
        return False

    async def _discover(self, ctx, kind):
        url_tmpl = MOVIES_URL if kind == "movie" else SHOWS_URL
        link_re  = SELECTORS["movie_link_re"] if kind == "movie" else SELECTORS["show_link_re"]
        base     = "/movie/" if kind == "movie" else "/tvshow/"
        seen     = {}
        page_no  = 1
        batch    = max(1, int(self.cfg["concurrency"]))
        max_pages = self.cfg["max_pages"]

        while not self._stopped():
            nums = list(range(page_no, page_no + batch))
            if max_pages:
                nums = [n for n in nums if n <= max_pages]
                if not nums: break
            self.status(f"Listing {kind}s — pages {nums[0]}–{nums[-1]}")
            results = await asyncio.gather(
                *[self._listing_page(ctx, url_tmpl.format(page=n), link_re) for n in nums],
                return_exceptions=True,
            )
            added = 0; empty_hit = False
            for n, res in zip(nums, results):
                if isinstance(res, Exception) or res is None:
                    self.log(f"[{kind}] page {n}: error/none"); continue
                if len(res) == 0:
                    empty_hit = True
                for hid in res:
                    if hid not in seen:
                        seen[hid] = BASE + base + hid; added += 1
                self.log(f"[{kind}] page {n}: {len(res)} items")
            self.log(f"[{kind}] total unique so far: {len(seen)} (+{added})")
            if added == 0 or empty_hit:
                break
            if max_pages and page_no + batch - 1 >= max_pages:
                break
            page_no += batch
        return list(seen.items())

    async def _listing_page(self, ctx, url, link_re):
        page = await ctx.new_page()
        try:
            if not await self._goto(page, url):
                return None
            html = await page.content()
            soup = BeautifulSoup(html, "html.parser")
            ids, s = [], set()
            for a in soup.find_all("a", href=True):
                m = link_re.search(a["href"])
                if m and m.group(1) not in s:
                    s.add(m.group(1)); ids.append(m.group(1))
            return ids
        finally:
            await page.close()

    async def _scrape_batch(self, ctx, targets, kind, sem):
        total = len(targets)
        done  = {"n": 0}

        async def worker(idx, hid, url):
            if self._stopped(): return
            async with sem:
                if self._stopped(): return
                page = await ctx.new_page()
                try:
                    if kind == "movie":
                        item = await self._scrape_movie(page, hid, url)
                        if item:
                            self.movies.append(asdict(item))
                            self.log(f"   ✓ [movie] {item.title} ({item.year})")
                    else:
                        item = await self._scrape_show(page, hid, url)
                        if item:
                            self.shows.append(asdict(item))
                            ne = sum(len(s["episodes"]) for s in item.seasons)
                            self.log(
                                f"   ✓ [show] {item.title} ({item.year}) "
                                f"— {len(item.seasons)} season(s), {ne} ep(s)"
                            )
                except Exception as e:
                    self.log(f"   ! failed {url}: {type(e).__name__}: {e}\n"
                             + "      " + traceback.format_exc().replace("\n", "\n      "))
                finally:
                    try: await page.close()
                    except Exception: pass
                done["n"] += 1
                self.progress(kind, done["n"], total)
                self.counts()
                self._completed += 1
                if self._completed % int(self.cfg["save_every"]) == 0:
                    self._save()

        await asyncio.gather(
            *[worker(i, hid, url) for i, (hid, url) in enumerate(targets, 1)],
            return_exceptions=True,
        )
        self._save()

    # ---- shared field extraction ----
    def _detail_common(self, soup):
        def meta(name):
            tag = (soup.find("meta", attrs={"property": name})
                   or soup.find("meta", attrs={"name": name}))
            return tag["content"].strip() if tag and tag.get("content") else ""

        title       = meta("og:title").split("|")[0].split(" - ")[0].strip()
        description = meta("og:description").strip()
        poster      = meta("og:image").strip()
        text        = soup.get_text(" ", strip=True)
        ym          = re.search(r"\b(19\d{2}|20\d{2})\b", text)
        year        = ym.group(1) if ym else ""
        language    = "مدبلج" if "مدبلج" in text else ("مترجم" if "مترجم" in text else "")
        backdrop    = self._find_backdrop(soup, poster)
        category    = self._find_category(soup)
        return dict(
            title=title, description=description, poster_url=poster,
            backdrop_url=backdrop, year=year, language=language, category=category,
        )

    def _find_backdrop(self, soup, poster):
        for el in soup.find_all(style=True):
            m = re.search(
                r'background-image\s*:\s*url\((["\']?)(.*?)\1\)',
                el.get("style", ""),
            )
            if m:
                u = m.group(2)
                if u and u != poster and u.startswith("http"):
                    return u
        for img in soup.find_all(["img", "source"]):
            u = (img.get("src") or img.get("data-src") or img.get("srcset") or "")
            u = u.split()[0] if u else ""
            if (u.startswith("http") and u != poster
                    and ("landscape" in u or "/w1280" in u or "backdrop" in u)):
                return u
        if "/storage/posters/" in poster and "portrait" in poster:
            return poster.replace("portrait", "landscape")
        return poster

    def _find_category(self, soup):
        ignore = SELECTORS["ignore_sections_text"]
        for a in soup.find_all("a", href=True):
            href = a["href"]
            if "/search/" in href or "search?tag=" in href:
                anc = a.find_parent(["section", "div"])
                anc_text = anc.get_text(" ", strip=True)[:60] if anc else ""
                if any(k in anc_text for k in ignore):
                    continue
                return a.get_text(strip=True)
        return ""

    # ---- movie detail ----
    async def _scrape_movie(self, page, hid, detail_url):
        if not await self._goto(page, detail_url): return None
        soup = BeautifulSoup(await page.content(), "html.parser")
        common = self._detail_common(soup)
        play_url = ""
        for a in soup.find_all("a", href=True):
            m = SELECTORS["movie_play_re"].search(a["href"])
            if m and "/movie/" not in a["href"]:
                play_url = BASE + "/play/" + m.group(1); break
        if not play_url:
            play_url = BASE + "/play/" + hid
        return Movie(id=hid, type="movie", detail_url=detail_url, play_url=play_url, **common)

    # ---- show detail ----
    async def _scrape_show(self, page, hid, detail_url):
        if not await self._goto(page, detail_url): return None
        soup = BeautifulSoup(await page.content(), "html.parser")
        common = self._detail_common(soup)
        title = common.get("title") or hid

        self.log(f"   → [show] scraping: {title}  ({hid})")

        # find the play link on the detail page (the "تشغيل" button)
        first_play = None
        for a in soup.find_all("a", href=True):
            if SELECTORS["episode_link_re"].search(a["href"]):
                first_play = a["href"]; break
        if first_play and first_play.startswith("/"):
            first_play = BASE + first_play

        seasons = []
        if first_play:
            seasons = await self._scrape_seasons(page, first_play, hid, title)
        else:
            self.log(f"      ! no play link found on detail page for '{title}' ({hid}); "
                     f"trying default play url")
            # last-ditch: many shows still resolve at /tvshow/{hid}/play (redirects)
            seasons = await self._scrape_seasons(
                page, f"{BASE}/tvshow/{hid}/play", hid, title
            )

        if not seasons:
            self.log(f"      !! '{title}' ({hid}) produced ZERO seasons/episodes")

        return TVShow(
            id=hid, type="tvshow", detail_url=detail_url, seasons=seasons, **common
        )

    # ------------------------------------------------------------------
    # SEASON / EPISODE SCRAPING  (rewritten)
    # ------------------------------------------------------------------
    def _attach_json_listener(self, page, sink):
        """
        Record every JSON response body the page fetches into `sink`
        (a list of (url, parsed_or_text)). The episode lists for each season
        come through here as fetch/xhr JSON.
        """
        async def _grab(resp):
            try:
                url = resp.url
                # skip our own page documents / obvious non-data
                ct = ""
                try:
                    ct = (resp.headers or {}).get("content-type", "")
                except Exception:
                    pass
                looks_json = ("json" in ct) or url.endswith(".json")
                if not looks_json:
                    return
                try:
                    data = await resp.json()
                except Exception:
                    try:
                        data = await resp.text()
                    except Exception:
                        return
                sink.append((url, data))
            except Exception:
                pass

        def _on_response(resp):
            try:
                asyncio.ensure_future(_grab(resp))
            except Exception:
                pass

        page.on("response", _on_response)
        return _on_response

    async def _find_season_tabs(self, page):
        """
        Return list of (label_text, ElementHandle) for every season tab.
        Tabs are <a href="#"> links whose text contains "الموسم".
        Group by parent and keep the largest group (the real tab bar).
        """
        keyword = SELECTORS["season_tab_keyword"]
        all_a = await page.query_selector_all('a[href="#"]')

        candidates = []
        for handle in all_a:
            try:
                txt = (await handle.inner_text() or "").strip()
            except Exception:
                continue
            if keyword in txt:
                candidates.append((txt, handle))

        if len(candidates) <= 1:
            return candidates

        parent_groups = {}
        for txt, handle in candidates:
            try:
                parent = await handle.evaluate_handle("el => el.parentElement")
                pid = await parent.evaluate(
                    "el => el.tagName + '.' + (el.className || '').split(' ').join('.')"
                )
            except Exception:
                pid = "unknown"
            parent_groups.setdefault(pid, []).append((txt, handle))

        best = max(parent_groups.values(), key=lambda g: len(g))
        return best

    async def _dom_play_anchors(self, page):
        """
        Read the LIVE rendered DOM (not a stale snapshot) and return a list of
        dicts describing every /play/ anchor currently visible.
        """
        try:
            return await page.evaluate(r"""() => {
                const out = [];
                const nodes = document.querySelectorAll(
                    'a[href*="/play/"], [data-href*="/play/"], [onclick*="/play/"]'
                );
                nodes.forEach(el => {
                    const href = el.getAttribute('href')
                        || el.getAttribute('data-href') || '';
                    const onclick = el.getAttribute('onclick') || '';
                    let card = el.closest(
                        'li, [class*="episode"], [class*="Episode"], [class*="ep-"], .card'
                    ) || el;
                    out.push({
                        href: href,
                        onclick: onclick,
                        text: (el.textContent || '').trim().slice(0, 140),
                        title: el.getAttribute('title') || '',
                        aria: el.getAttribute('aria-label') || '',
                        card: (card.textContent || '').trim().slice(0, 180)
                    });
                });
                return out;
            }""")
        except Exception:
            return []

    async def _dom_episode_ids(self, page):
        """Return the SET of numeric play-ids currently rendered in the live DOM.
        Numeric ids are episode play-ids; this is the source of truth for which
        episodes belong to the currently-shown season."""
        try:
            ids = await page.evaluate(r"""() => {
                const s = new Set();
                document.querySelectorAll(
                    'a[href*="/play/"],[data-href*="/play/"],[onclick*="/play/"]'
                ).forEach(el => {
                    const h = el.getAttribute('href')
                        || el.getAttribute('data-href')
                        || el.getAttribute('onclick') || '';
                    const m = h.match(/\/play\/(\d+)/);
                    if (m) s.add(m[1]);
                });
                return Array.from(s);
            }""")
            return set(ids or [])
        except Exception:
            return set()

    async def _js_click(self, handle):
        """Click via JS to bypass Playwright visibility checks (tabs live in an
        overflow-hidden scroll container)."""
        try:
            await handle.evaluate(r"""el => {
                el.scrollIntoView({block:'nearest', inline:'center'});
                el.dispatchEvent(new MouseEvent('mousedown', {bubbles:true}));
                el.dispatchEvent(new MouseEvent('mouseup',   {bubbles:true}));
                el.dispatchEvent(new MouseEvent('click',     {bubbles:true}));
            }""")
        except Exception:
            pass

    async def _force_click(self, handle):
        """Stronger click for an ALREADY-ACTIVE tab: strip any active/selected/
        current classes from the element + ancestors first, so the SPA stops
        treating the tab as the current selection and actually fires its handler."""
        try:
            await handle.evaluate(r"""el => {
                let n = el;
                for (let i = 0; i < 5 && n; i++) {
                    if (n.classList) {
                        [...n.classList].forEach(c => {
                            if (/active|selected|current/i.test(c))
                                n.classList.remove(c);
                        });
                    }
                    if (n.getAttribute && n.getAttribute('aria-selected') === 'true')
                        n.setAttribute('aria-selected', 'false');
                    n = n.parentElement;
                }
                el.scrollIntoView({block:'nearest', inline:'center'});
                el.dispatchEvent(new MouseEvent('mousedown', {bubbles:true}));
                el.dispatchEvent(new MouseEvent('mouseup',   {bubbles:true}));
                el.dispatchEvent(new MouseEvent('click',     {bubbles:true}));
                el.click && el.click();
            }""")
        except Exception:
            pass

    async def _wait_any_episodes(self, page, max_wait=6.0, poll=0.25):
        """Poll until at least one episode play-id is rendered, or timeout."""
        elapsed = 0.0
        while elapsed < max_wait:
            await asyncio.sleep(poll)
            elapsed += poll
            if await self._dom_episode_ids(page):
                return True
        return False

    async def _wait_switch(self, page, avoid_ids, max_wait=10.0, poll=0.25):
        """
        Poll until the rendered episode-id set is non-empty AND different from
        `avoid_ids` AND stable for two consecutive polls. Returns the id set
        (or whatever is present at timeout). Used to confirm a tab click really
        switched the list to a NEW season rather than leaving the old one up.
        """
        prev = None
        elapsed = 0.0
        while elapsed < max_wait:
            await asyncio.sleep(poll)
            elapsed += poll
            cur = await self._dom_episode_ids(page)
            if cur and cur != avoid_ids:
                if cur == prev:
                    return cur            # stable, switched
                prev = cur
        return await self._dom_episode_ids(page)

    @staticmethod
    def _pid(ep):
        m = re.search(r"/play/(\d+)", ep.play_url)
        return m.group(1) if m else ep.play_url

    def _read_current_season(self, anchors, captured, show_hid):
        """
        Build the episode list for the season currently rendered.

        Membership comes from the LIVE DOM (authoritative — avoids the JSON
        capture-buffer double-counting across seasons). Titles/numbers are then
        enriched from captured JSON (a global id->title map). If the DOM has no
        episodes at all, fall back to whatever JSON we captured.
        """
        dom_eps  = self._episodes_from_dom(anchors, show_hid)
        json_eps = self._episodes_from_captured(captured, show_hid)

        if dom_eps:
            jmap = {self._pid(e): e for e in json_eps}
            for e in dom_eps:
                pid = self._pid(e)
                j = jmap.get(pid)
                if j:
                    if (not e.title or e.title.isdigit()) and j.title:
                        e.title = j.title
                    if not e.number and j.number:
                        e.number = j.number
            return self._finalize_list(dom_eps)

        return self._finalize_list(json_eps)

    async def _scrape_seasons(self, page, player_url, show_hid, show_title):
        """
        Navigate to the player and scrape every season's episodes.

        Root issue handled here: the season that is ALREADY active when the page
        loads never renders its episode list, because clicking an already-active
        tab is a no-op for the site's SPA. So for every target tab we first click
        a DIFFERENT tab (making the target non-active), then click the target and
        wait for the list to actually switch. Single-season shows (only one tab,
        permanently active) get a dedicated escape path.
        """
        captured = []
        self._attach_json_listener(page, captured)

        if not await self._goto(page, player_url):
            self.log(f"      ! could not open player for '{show_title}'")
            return []

        await self._wait_any_episodes(page, max_wait=6.0)
        tabs = await self._find_season_tabs(page)
        self.log(f"      [{show_title}] season tab(s) detected: {len(tabs)}")

        # ---------------- single season (0 or 1 tab) ----------------
        if len(tabs) <= 1:
            label  = tabs[0][0] if tabs else ""
            handle = tabs[0][1] if tabs else None
            eps = await self._read_single_season(page, show_hid, captured,
                                                 handle, show_title)
            if eps:
                self.log(f"      [{show_title}] single season "
                         f"('{label or '—'}'): {len(eps)} ep(s)")
                return [asdict(Season(self._season_number(label, 1), label,
                                      [asdict(e) for e in eps]))]
            self.log(f"      [{show_title}] !! single season produced 0 episodes")
            await self._diagnose_empty(page, captured, show_hid, show_title)
            return []

        # ---------------- multi season ----------------
        seasons = []
        seen_sets = []
        n = len(tabs)

        for i, (label, handle) in enumerate(tabs):
            if self._stopped(): break
            season_num = self._season_number(label, i + 1)

            # 1) make the target non-active by selecting a different tab first
            other_handle = tabs[(i + 1) % n][1]
            await self._js_click(other_handle)
            await self._wait_any_episodes(page, max_wait=6.0)
            other_ids = await self._dom_episode_ids(page)

            # 2) now select the target; wait for the list to actually switch
            await self._js_click(handle)
            target_ids = await self._wait_switch(page, other_ids, max_wait=10.0)

            # 3) if it didn't switch, retry once with the stronger click
            if (not target_ids) or target_ids == other_ids:
                await self._force_click(handle)
                target_ids = await self._wait_switch(page, other_ids, max_wait=8.0)

            try:
                await page.wait_for_load_state("networkidle", timeout=3000)
            except PWTimeout:
                pass

            anchors = await self._dom_play_anchors(page)
            eps = self._read_current_season(anchors, captured, show_hid)
            ids_set = frozenset(self._pid(e) for e in eps)

            dup = ids_set and ids_set in seen_sets
            seen_sets.append(ids_set)
            seasons.append(asdict(Season(season_num, label,
                                         [asdict(e) for e in eps])))

            flag = "  !! DUPLICATE (click likely ignored)" if dup else ""
            self.log(f"      [{show_title}] S{season_num} '{label}': "
                     f"{len(eps)} ep(s){flag}")
            if not eps:
                await self._diagnose_empty(page, captured, show_hid,
                                           show_title, season=label)

        if sum(len(s["episodes"]) for s in seasons) == 0:
            self.log(f"      [{show_title}] !! all seasons empty")
            await self._diagnose_empty(page, captured, show_hid, show_title)
        return seasons

    async def _read_single_season(self, page, show_hid, captured, handle, show_title):
        """
        Read the lone season's episodes. Because its tab is permanently active,
        a normal click is a no-op, so we try escalating strategies until the
        episode list appears.
        """
        # A) maybe it already rendered on load
        eps = self._read_current_season(
            await self._dom_play_anchors(page), captured, show_hid)
        if eps:
            return eps

        # B) plain click
        if handle:
            await self._js_click(handle)
            await self._wait_any_episodes(page, max_wait=6.0)
            eps = self._read_current_season(
                await self._dom_play_anchors(page), captured, show_hid)
            if eps:
                return eps

            # C) force-click (strip active classes so the SPA re-fires)
            await self._force_click(handle)
            await self._wait_any_episodes(page, max_wait=6.0)
            eps = self._read_current_season(
                await self._dom_play_anchors(page), captured, show_hid)
            if eps:
                return eps

        # D) reload fresh and wait generously
        try:
            await page.reload(wait_until="domcontentloaded")
            await self._wait_any_episodes(page, max_wait=12.0)
            eps = self._read_current_season(
                await self._dom_play_anchors(page), captured, show_hid)
            if eps:
                return eps
        except Exception:
            pass

        # E) last resort: whatever JSON we captured
        return self._finalize_list(self._episodes_from_captured(captured, show_hid))

    async def _diagnose_empty(self, page, captured, show_hid, show_title, season=""):
        """When a season comes back empty, log WHY: how many candidate elements
        exist in the live DOM and the shape of every captured JSON payload, so
        the exact markup / API field names are visible directly in the log."""
        try:
            info = await page.evaluate(r"""() => {
                const q = s => { try { return document.querySelectorAll(s).length; }
                                 catch(e){ return -1; } };
                return {
                    a_play:       q('a[href*="/play/"]'),
                    data_play:    q('[data-href*="/play/"]'),
                    onclick_play: q('[onclick*="/play/"]'),
                    a_total:      q('a'),
                    li:           q('li'),
                    button:       q('button'),
                    img:          q('img'),
                    body_chars:   (document.body ? document.body.innerHTML.length : 0)
                };
            }""")
            self.log(f"      [diag] {show_title} {season}: live-DOM counts = {info}")
        except Exception as e:
            self.log(f"      [diag] DOM probe failed: {e}")

        for i, (url, data) in enumerate(captured[-5:]):
            try:
                if isinstance(data, dict):
                    shape = "dict keys=[" + ",".join(list(data.keys())[:14]) + "]"
                elif isinstance(data, list):
                    shape = f"list len={len(data)}"
                    if data and isinstance(data[0], dict):
                        shape += " item0 keys=[" + ",".join(list(data[0].keys())[:14]) + "]"
                else:
                    shape = type(data).__name__ + f" len={len(str(data))}"
            except Exception:
                shape = "?"
            self.log(f"      [diag] json[{i}] {url[:95]}  ->  {shape}")

        await self._maybe_debug_dump(page, captured, show_hid, show_title)

    # ---- episode extraction: from captured JSON ----
    def _episodes_from_captured(self, captured, show_hid):
        found = {}
        for url, data in captured:
            try:
                self._walk_json_for_episodes(data, show_hid, found)
            except Exception:
                continue
        return self._finalize(found)

    @staticmethod
    def _looks_like_episode_label(s):
        """True only for strings that carry a real episode marker, so that
        season/show wrappers (e.g. 'Ben 10 S01') are NOT mistaken for
        episodes just because they contain a stray number."""
        if not s:
            return False
        return bool(
            re.search(r"الحلقة", s)
            or re.search(r"[eE]\d", s)        # e01 / E9 (an episode marker)
            or re.match(r"^\s*\d", s)         # "1. ..." / "001"
        )

    def _walk_json_for_episodes(self, node, show_hid, found):
        """
        Recursively scan arbitrary JSON for episode-like objects.

        An object qualifies as an episode iff:
          * it has a NUMERIC id-ish field (the play id; show/recommendation ids
            are hex hashes such as '6a2aeb...' and are ignored), AND
          * it has an explicit episode-NUMBER field, OR a title that carries a
            real episode marker (الحلقة / eNN / leading digit).
        Container objects (a season/show carrying an 'episodes' list) are never
        themselves treated as episodes — only their children are.
        """
        ID_KEYS    = ("id", "episode_id", "video_id", "play_id", "vid", "ep_id")
        NUM_KEYS   = ("episode", "episode_number", "number", "ep", "order",
                      "no", "index", "rank")
        TITLE_KEYS = ("title", "name", "label", "episode_title", "arabic_title",
                      "title_ar", "name_ar", "original_title", "ep_title")
        LIST_CONTAINER_KEYS = ("episodes", "eps", "videos", "items", "list",
                               "results", "data", "seasons")

        if isinstance(node, dict):
            # Is this object a container (has a child list of dicts)? If so it
            # is a season/show wrapper, not an episode itself.
            is_container = any(
                isinstance(node.get(k), list)
                and any(isinstance(x, dict) for x in node.get(k))
                for k in LIST_CONTAINER_KEYS
            )

            ep_id = None
            for k in ID_KEYS:
                if k in node:
                    v = node[k]
                    if isinstance(v, bool):
                        continue
                    if isinstance(v, int):
                        ep_id = v; break
                    if isinstance(v, str) and v.isdigit():
                        ep_id = int(v); break

            title = ""
            for k in TITLE_KEYS:
                v = node.get(k)
                if isinstance(v, str) and v.strip():
                    title = v.strip(); break

            num = 0
            has_num_key = False
            for k in NUM_KEYS:
                v = node.get(k)
                if isinstance(v, bool):
                    continue
                if isinstance(v, int):
                    num = v; has_num_key = True; break
                if isinstance(v, str) and v.strip().isdigit():
                    num = int(v.strip()); has_num_key = True; break
            if not num and title:
                num = self._episode_number(title)

            qualifies = (
                not is_container
                and ep_id is not None
                and (has_num_key or self._looks_like_episode_label(title))
            )
            if qualifies:
                eid = str(ep_id)
                if eid not in found or (title and not found[eid].title):
                    found[eid] = Episode(
                        num, title, f"{BASE}/tvshow/{show_hid}/play/{eid}"
                    )

            for v in node.values():
                if isinstance(v, (dict, list)):
                    self._walk_json_for_episodes(v, show_hid, found)

        elif isinstance(node, list):
            for item in node:
                if isinstance(item, (dict, list)):
                    self._walk_json_for_episodes(item, show_hid, found)

    # ---- episode extraction: from live DOM anchors ----
    def _episodes_from_dom(self, anchors, show_hid):
        found = {}
        ep_re = SELECTORS["episode_link_re"]
        any_re = SELECTORS["any_play_re"]
        for a in anchors:
            href    = a.get("href") or ""
            onclick = a.get("onclick") or ""
            blob    = href + " " + onclick

            ep_id = None
            m = ep_re.search(blob)
            if m:
                ep_id = m.group(2)
            else:
                m2 = any_re.search(blob)
                if m2:
                    ep_id = m2.group(1)
            if not ep_id:
                continue

            # pick the best human label available
            label = (a.get("title") or "").strip() or (a.get("aria") or "").strip()
            text  = (a.get("text") or "").strip()
            card  = (a.get("card") or "").strip()
            # prefer a label that actually contains an episode marker
            best = ""
            for cand in (label, text, card):
                if cand and ("الحلقة" in cand or re.search(r"[eE]\d", cand)
                             or re.match(r"^\s*\d", cand)):
                    best = cand; break
            if not best:
                best = label or text or card
            best = re.sub(r"\s+", " ", best).strip()

            num = self._episode_number(best)
            play_url = f"{BASE}/tvshow/{show_hid}/play/{ep_id}"
            if ep_id not in found or (best and not found[ep_id].title):
                found[ep_id] = Episode(num, best, play_url)
        return self._finalize(found)

    def _merge_episodes(self, primary, secondary):
        """Merge two episode lists keyed by play-id. `primary` wins on title,
        `secondary` fills gaps."""
        by_id = {}
        def key(e):
            m = re.search(r"/play/(\d+)", e.play_url)
            return m.group(1) if m else e.play_url
        for e in secondary:
            by_id[key(e)] = e
        for e in primary:
            k = key(e)
            if k in by_id:
                ex = by_id[k]
                ex.title  = e.title or ex.title
                ex.number = e.number or ex.number
            else:
                by_id[k] = e
        return self._finalize_list(list(by_id.values()))

    def _finalize(self, found_dict):
        return self._finalize_list(list(found_dict.values()))

    def _finalize_list(self, eps):
        eps.sort(key=lambda e: (e.number if e.number else 10 ** 9, e.title))
        counter = 1
        for e in eps:
            if not e.number:
                e.number = counter
            counter = e.number + 1
        return eps

    def _season_number(self, txt, fallback):
        ordinals = {
            "الأول": 1, "الثاني": 2, "الثالث": 3, "الرابع": 4,
            "الخامس": 5, "السادس": 6, "السابع": 7, "الثامن": 8,
            "التاسع": 9, "العاشر": 10,
        }
        for word, num in ordinals.items():
            if word in txt:
                return num
        m = re.search(r"[Ss](\d{1,3})", txt)
        if m:
            return int(m.group(1))
        m = re.search(r"(\d{1,3})", txt)
        if m:
            return int(m.group(1))
        return fallback

    def _episode_number(self, label):
        if not label:
            return 0
        # explicit episode marker eNN / ENN (not part of S0N)
        m = re.search(r"[eE](\d{1,4})(?!\d)", label)
        if m:
            return int(m.group(1))
        # Arabic "الحلقة N"
        m = re.search(r"(?:الحلقة|حح?)\s*(\d{1,4})", label)
        if m:
            return int(m.group(1))
        # leading number
        m = re.match(r"^\s*(\d{1,4})\b", label)
        if m:
            return int(m.group(1))
        # last standalone number not glued to letters
        nums = re.findall(r"(?<![A-Za-z])(\d{1,4})(?!\d)", label)
        if nums:
            return int(nums[-1])
        return 0

    # ---- debug dump on failure ----
    async def _maybe_debug_dump(self, page, captured, show_hid, show_title):
        if not self.cfg.get("debug_dump"):
            return
        try:
            os.makedirs(self._debug_dir, exist_ok=True)
            safe = re.sub(r"[^\w\-]+", "_", show_title)[:40] or show_hid
            base = os.path.join(self._debug_dir, f"{safe}_{show_hid}")
            html = await page.content()
            with open(base + ".html", "w", encoding="utf-8") as f:
                f.write(html)
            dump = []
            for url, data in captured:
                try:
                    s = json.dumps(data, ensure_ascii=False)[:4000]
                except Exception:
                    s = str(data)[:4000]
                dump.append({"url": url, "body_preview": s})
            with open(base + ".captured.json", "w", encoding="utf-8") as f:
                json.dump(dump, f, ensure_ascii=False, indent=2)
            self.log(f"      [debug] dumped HTML + {len(captured)} JSON payload(s) "
                     f"to {base}.* — inspect these to refine field names")
        except Exception as e:
            self.log(f"      [debug] dump failed: {e}")

    # ---- persistence ----
    def _save(self):
        data = {
            "source":       BASE,
            "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "language":     "dub",
            "counts":       {"movies": len(self.movies), "shows": len(self.shows)},
            "movies":       self.movies,
            "tvshows":      self.shows,
        }
        path = self.cfg["out_path"]
        tmp  = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)


# ============================================================================
# GUI
# ============================================================================
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Stardima Scraper — Parallel (Fixed v2)")
        self.geometry("780x680"); self.minsize(700, 580)
        self.msg_queue  = queue.Queue()
        self.stop_event = threading.Event()
        self.worker     = None
        self._build_ui()
        self.after(120, self._poll_queue)

    def _build_ui(self):
        pad = dict(padx=8, pady=4)
        top = ttk.LabelFrame(self, text="Settings"); top.pack(fill="x", **pad)

        row = ttk.Frame(top); row.pack(fill="x", padx=8, pady=4)
        ttk.Label(row, text="Output file:").pack(side="left")
        self.out_var = tk.StringVar(value=DEFAULTS["out_path"])
        ttk.Entry(row, textvariable=self.out_var).pack(side="left", fill="x", expand=True, padx=6)
        ttk.Button(row, text="Browse…", command=self._browse).pack(side="left")

        row2 = ttk.Frame(top); row2.pack(fill="x", padx=8, pady=4)
        self.movies_var  = tk.BooleanVar(value=True)
        self.shows_var   = tk.BooleanVar(value=True)
        self.headless_var= tk.BooleanVar(value=True)
        self.block_var   = tk.BooleanVar(value=True)
        self.debug_var   = tk.BooleanVar(value=True)
        ttk.Checkbutton(row2, text="Movies",                variable=self.movies_var ).pack(side="left")
        ttk.Checkbutton(row2, text="TV shows",              variable=self.shows_var  ).pack(side="left", padx=(10,0))
        ttk.Checkbutton(row2, text="Headless",              variable=self.headless_var).pack(side="left", padx=(18,0))
        ttk.Checkbutton(row2, text="Block images/CSS/fonts",variable=self.block_var ).pack(side="left", padx=(18,0))
        ttk.Checkbutton(row2, text="Debug dump",            variable=self.debug_var ).pack(side="left", padx=(18,0))

        row3 = ttk.Frame(top); row3.pack(fill="x", padx=8, pady=4)
        ttk.Label(row3, text="Concurrency:").pack(side="left")
        self.conc_var = tk.IntVar(value=DEFAULTS["concurrency"])
        ttk.Spinbox(row3, from_=1, to=32, width=5, textvariable=self.conc_var).pack(side="left", padx=6)
        ttk.Label(row3, text="Max pages (0=all):").pack(side="left", padx=(16,0))
        self.maxpages_var = tk.IntVar(value=DEFAULTS["max_pages"])
        ttk.Spinbox(row3, from_=0, to=999, width=5, textvariable=self.maxpages_var).pack(side="left", padx=6)
        ttk.Label(row3, text="Delay (s):").pack(side="left", padx=(16,0))
        self.delay_var = tk.DoubleVar(value=DEFAULTS["delay"])
        ttk.Spinbox(row3, from_=0.0, to=10.0, increment=0.1, width=5,
                    textvariable=self.delay_var).pack(side="left", padx=6)
        ttk.Label(row3, text="(TEST: pages=1, uncheck Headless)").pack(side="left", padx=(12,0))

        prog = ttk.LabelFrame(self, text="Progress"); prog.pack(fill="x", **pad)
        self.status_var = tk.StringVar(value="Idle")
        ttk.Label(prog, textvariable=self.status_var).pack(anchor="w", padx=8, pady=(6,2))

        mrow = ttk.Frame(prog); mrow.pack(fill="x", padx=8, pady=2)
        ttk.Label(mrow, text="Movies", width=8).pack(side="left")
        self.movie_bar = ttk.Progressbar(mrow, mode="determinate")
        self.movie_bar.pack(side="left", fill="x", expand=True, padx=6)
        self.movie_count = ttk.Label(mrow, text="0", width=10); self.movie_count.pack(side="left")

        srow = ttk.Frame(prog); srow.pack(fill="x", padx=8, pady=2)
        ttk.Label(srow, text="Shows", width=8).pack(side="left")
        self.show_bar = ttk.Progressbar(srow, mode="determinate")
        self.show_bar.pack(side="left", fill="x", expand=True, padx=6)
        self.show_count = ttk.Label(srow, text="0", width=10); self.show_count.pack(side="left")

        brow = ttk.Frame(self); brow.pack(fill="x", **pad)
        self.start_btn = ttk.Button(brow, text="Start",  command=self._start)
        self.start_btn.pack(side="left")
        self.stop_btn  = ttk.Button(brow, text="Stop",   command=self._stop, state="disabled")
        self.stop_btn.pack(side="left", padx=6)
        ttk.Button(brow, text="Open output folder", command=self._open_folder).pack(side="left", padx=6)

        logf = ttk.LabelFrame(self, text="Log"); logf.pack(fill="both", expand=True, **pad)
        self.log_txt = tk.Text(logf, height=14, wrap="word", state="disabled")
        self.log_txt.pack(side="left", fill="both", expand=True, padx=(6,0), pady=6)
        sb = ttk.Scrollbar(logf, command=self.log_txt.yview); sb.pack(side="right", fill="y", pady=6)
        self.log_txt.config(yscrollcommand=sb.set)

    def _browse(self):
        path = filedialog.asksaveasfilename(
            defaultextension=".json",
            filetypes=[("JSON", "*.json")],
            initialfile="catalog.json",
        )
        if path: self.out_var.set(path)

    def _open_folder(self):
        folder = os.path.dirname(self.out_var.get()) or "."
        try:
            if os.name == "nt": os.startfile(folder)
            elif sys.platform == "darwin": os.system(f'open "{folder}"')
            else: os.system(f'xdg-open "{folder}"')
        except Exception:
            messagebox.showinfo("Folder", folder)

    def _append_log(self, text):
        self.log_txt.config(state="normal")
        self.log_txt.insert("end", text + "\n")
        self.log_txt.see("end")
        self.log_txt.config(state="disabled")

    def _start(self):
        if self.worker and self.worker.is_alive(): return
        if not self.movies_var.get() and not self.shows_var.get():
            messagebox.showwarning("Nothing to do", "Select Movies and/or TV shows.")
            return
        cfg = {
            "out_path":       self.out_var.get().strip() or DEFAULTS["out_path"],
            "delay":          float(self.delay_var.get()),
            "nav_timeout":    DEFAULTS["nav_timeout"],
            "headless":       bool(self.headless_var.get()),
            "max_pages":      int(self.maxpages_var.get()),
            "concurrency":    int(self.conc_var.get()),
            "block_resources": bool(self.block_var.get()),
            "do_movies":      bool(self.movies_var.get()),
            "do_shows":       bool(self.shows_var.get()),
            "save_every":     DEFAULTS["save_every"],
            "debug_dump":     bool(self.debug_var.get()),
        }
        self.stop_event.clear()
        self.movie_bar["value"] = 0; self.show_bar["value"] = 0
        self._append_log("--- starting ---")
        scraper = StardimaScraper(cfg, self.msg_queue, self.stop_event)
        self.worker = threading.Thread(target=scraper.run, daemon=True)
        self.worker.start()
        self.start_btn.config(state="disabled")
        self.stop_btn.config(state="normal")

    def _stop(self):
        self.stop_event.set(); self.status_var.set("Stopping…")
        self._append_log("--- stop requested (in-flight items finish) ---")

    def _poll_queue(self):
        try:
            while True:
                kind, payload = self.msg_queue.get_nowait()
                if kind == "log":
                    self._append_log(payload)
                elif kind == "status":
                    self.status_var.set(payload)
                elif kind == "counts":
                    m, s = payload
                    self.movie_count.config(text=str(m))
                    self.show_count.config(text=str(s))
                elif kind == "progress":
                    which, done, total = payload
                    bar = self.movie_bar if which == "movie" else self.show_bar
                    bar["maximum"] = max(total, 1); bar["value"] = done
                elif kind == "error":
                    messagebox.showerror("Error", payload)
                elif kind == "done":
                    self.start_btn.config(state="normal")
                    self.stop_btn.config(state="disabled")
        except queue.Empty:
            pass
        self.after(120, self._poll_queue)


if __name__ == "__main__":
    App().mainloop()
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Carateen probe GUI  (carateen.tv)
=================================

Paste a carateen.tv link (a `/watch/<id>` page, a show slug, or `/music`) and
this tool opens it in a real (Playwright) browser, lets the site's own
JavaScript run, and reports **how hard the title is to extract** — without us
having to reverse the site's encryption by hand.

WHY A BROWSER (and not plain HTTP like the Stardima resolver)
-------------------------------------------------------------
carateen.tv is a Cloudflare-fronted Vue/Vite SPA. Its JSON API
(`/api/sp/episodes?slug=...`, `/api/sp/recentEpisodes`, the music endpoints)
does NOT return readable JSON — every response is AES-encrypted:

    {"iv":"<32 hex>", "encryptedData":"<hex>"}

The AES key lives inside the obfuscated JS bundle, so a plain HTTP client sees
only ciphertext. Rather than crack the key up front, this probe loads the page,
lets the site decrypt everything itself, and then observes the RESULT:

  1. NETWORK CAPTURE  — every media request the player fires after decryption
     (.m3u8 / .mp4 / .mp3 / .m4a / .ts, plus known embed hosts). This is the
     real, decrypted playable URL.
  2. LIVE DOM         — the <video>/<audio> element src, any <iframe> src, and
     the rendered episode/track list.
  3. DECRYPT HOOK     — wraps window.crypto.subtle.decrypt and (if present)
     CryptoJS so the plaintext JSON the site produces is dumped straight into
     the log. If this fires, a pure-HTTP Dart/Python resolver becomes possible
     (recover the key once, decrypt forever, no browser at runtime).

Read the log + the RESULT summary to judge difficulty:
  * media URL is a direct .m3u8/.mp4  -> EASY (one hop, like Arabic Toons).
  * media URL is an embed host        -> MEDIUM (needs a 2nd extraction hop,
                                          like the Stardima host resolver).
  * only encrypted API, nothing plays -> HARD (key/DRM barrier; needs the hook
                                          output or a deobfuscation pass).

INSTALL (one time):
    pip install playwright
    playwright install chromium
RUN:
    python carateen_probe.py
"""

import asyncio
import json
import queue
import re
import threading
import time
import traceback

import tkinter as tk
from tkinter import ttk, messagebox

try:
    from playwright.async_api import async_playwright, TimeoutError as PWTimeout
except ImportError:
    async_playwright = None
    PWTimeout = Exception


BASE = "https://carateen.tv"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")

# Anything matching these is a real, decrypted media stream the player loaded.
MEDIA_RE = re.compile(r"\.(m3u8|mp4|mp3|m4a|ts|aac|webm)(\?|$)", re.I)
# Third-party embed hosts (a hit here means a second extraction hop is needed).
EMBED_HINTS = ("embed", "player", "iframe", "strema", "uqload", "lulustream",
               "dood", "vidmoly", "mp4upload", "ok.ru", "youtube", "youtu.be")

# JS injected before any site script runs: it wraps the decryption primitives so
# whatever plaintext the site decrypts is posted back to us via console.log.
HOOK_JS = r"""
(() => {
  const tag = '[[CARATEEN-PLAINTEXT]]';
  const dec = new TextDecoder();
  // Catch-all: the app JSON.parse()s the decrypted string. Vite bundles the
  // crypto lib as a local module (not on window), so wrapping JSON.parse is the
  // most reliable way to see the plaintext regardless of which AES impl is used.
  try {
    const oj = JSON.parse;
    let n = 0;
    JSON.parse = function(s, r) {
      if (typeof s === 'string' && s.length > 100 && n < 12 &&
          (s[0] === '{' || s[0] === '[') && s.indexOf('"@context"') === -1) {
        n++;
        console.log(tag + ' jsonparse ' + s.slice(0, 6000));
      }
      return oj.call(this, s, r);
    };
  } catch (e) {}
  try {
    const orig = crypto.subtle.decrypt.bind(crypto.subtle);
    crypto.subtle.decrypt = async function(alg, key, data) {
      const out = await orig(alg, key, data);
      try {
        const s = dec.decode(out);
        console.log(tag + ' subtle ' + s.slice(0, 4000));
      } catch (e) {}
      return out;
    };
  } catch (e) {}
  // CryptoJS is loaded lazily; poll for it and wrap AES.decrypt when it appears.
  let tries = 0;
  const iv = setInterval(() => {
    tries++;
    if (window.CryptoJS && window.CryptoJS.AES && !window.__cjHooked) {
      window.__cjHooked = true;
      const o = window.CryptoJS.AES.decrypt.bind(window.CryptoJS.AES);
      window.CryptoJS.AES.decrypt = function(...a) {
        const r = o(...a);
        try {
          const s = r.toString(window.CryptoJS.enc.Utf8);
          if (s) console.log(tag + ' cryptojs ' + s.slice(0, 4000));
        } catch (e) {}
        return r;
      };
    }
    if (tries > 60) clearInterval(iv);
  }, 250);
})();
"""


class Probe:
    def __init__(self, cfg, q: "queue.Queue", stop: threading.Event):
        self.cfg, self.q, self.stop = cfg, q, stop
        self.api_hits = []      # (endpoint, iv-or-'')
        self.media_hits = []    # decrypted media urls
        self.embed_hits = []    # embed-host urls
        self.plaintext = []     # decrypted JSON snippets from the hook
        self.dom = {}

    def log(self, t): self.q.put(("log", t))
    def status(self, t): self.q.put(("status", t))

    def run(self):
        if async_playwright is None:
            self.q.put(("error",
                "Playwright missing.\n\npip install playwright\nplaywright install chromium"))
            self.q.put(("done", None)); return
        try:
            asyncio.run(self._go())
        except Exception:
            self.log("\n!!! ERROR:\n" + traceback.format_exc())
        finally:
            self.q.put(("done", None))

    def _normalize(self, raw):
        raw = raw.strip()
        if raw.isdigit():
            return f"{BASE}/watch/{raw}"
        if raw.startswith("http"):
            return raw
        if raw.startswith("/"):
            return BASE + raw
        return f"{BASE}/{raw}"

    async def _go(self):
        url = self._normalize(self.cfg["url"])
        self.log(f"=== probing: {url} ===")
        self.status("launching browser…")
        async with async_playwright() as pw:
            browser = await pw.chromium.launch(
                headless=self.cfg["headless"],
                args=["--disable-blink-features=AutomationControlled", "--no-sandbox"],
            )
            ctx = await browser.new_context(
                user_agent=UA, viewport={"width": 1366, "height": 900}, locale="ar")
            await ctx.add_init_script(HOOK_JS)
            # carateen is ad-gated: clicking anything can fire a pop-under /
            # redirect to a malvertising decoy. Keep the probe on the player by
            # aborting navigations/frames to non-carateen ad hosts.
            await ctx.route("**/*", self._route_ads)
            page = await ctx.new_page()
            page.on("response", lambda r: asyncio.ensure_future(self._on_resp(r)))
            page.on("request", self._on_req)
            page.on("console", self._on_console)

            self.status("loading page…")
            try:
                await page.goto(url, timeout=45000, wait_until="domcontentloaded")
            except Exception as e:
                self.log(f"   ! initial load: {type(e).__name__}: {e}")
            try:
                await page.wait_for_load_state("networkidle", timeout=12000)
            except PWTimeout:
                pass

            # try to trigger playback: click the first play/episode control
            await self._try_play(page)

            # let media requests fire
            settle = int(self.cfg["settle"])
            self.log(f"   … watching network for {settle}s (trigger playback if needed)")
            for _ in range(settle):
                if self.stop.is_set(): break
                await asyncio.sleep(1)

            await self._read_dom(page)
            await ctx.close(); await browser.close()

        self._report()

    async def _route_ads(self, route):
        try:
            u = route.request.url.lower()
            rt = route.request.resource_type
            bad = ("fhvfd", "viieuvkf", "kettledrooping", "yamli",
                   "edwardspeedingchat", "llvpn", "doubleclick", "googlesyndication",
                   "popads", "propeller", "adnxs")
            if any(b in u for b in bad) or (rt == "document" and "carateen" not in u):
                await route.abort(); return
            await route.continue_()
        except Exception:
            try: await route.continue_()
            except Exception: pass

    async def _try_play(self, page):
        # First pick an episode (the per-episode source call only fires on
        # selection), then hit any player control. Ad-redirect documents are
        # already aborted by _route_ads, so a same-site episode click is safe.
        ep_sels = ('[class*="episode" i] a', '[class*="episode" i]',
                   ".episodes a", "li a[href*='/watch/']", ".ep-item")
        for sel in ep_sels:
            try:
                el = await page.query_selector(sel)
                if el:
                    await el.click(timeout=2000)
                    self.log(f"   → selected episode via '{sel}'")
                    await asyncio.sleep(2.5)
                    break
            except Exception:
                continue
        for sel in (".vjs-big-play-button", ".plyr__control--overlaid",
                    'button[aria-label*="play" i]', ".jw-icon-display",
                    "video", ".player button", ".play-btn"):
            try:
                el = await page.query_selector(sel)
                if el:
                    await el.click(timeout=1500)
                    self.log(f"   → clicked '{sel}' to start playback")
                    await asyncio.sleep(1.5)
                    return
            except Exception:
                continue

    def _on_req(self, req):
        u = req.url
        if MEDIA_RE.search(u) and u not in self.media_hits:
            self.media_hits.append(u)
            self.log(f"   ♪ MEDIA request: {u[:140]}")
        elif any(h in u.lower() for h in EMBED_HINTS) and "carateen" not in u:
            if u not in self.embed_hits:
                self.embed_hits.append(u)
                self.log(f"   ▸ embed/host request: {u[:140]}")

    async def _on_resp(self, resp):
        try:
            u = resp.url
            if "/api/" not in u:
                return
            iv = ""
            try:
                body = await resp.text()
                m = re.search(r'"iv"\s*:\s*"([0-9a-f]+)"', body)
                if m:
                    iv = m.group(1)
            except Exception:
                pass
            ep = u.replace(BASE, "")
            self.api_hits.append((ep, iv))
            self.log(f"   · API {ep[:80]}  {'[ENCRYPTED iv=' + iv[:8] + '…]' if iv else ''}")
        except Exception:
            pass

    def _on_console(self, msg):
        try:
            t = msg.text
        except Exception:
            return
        if "[[CARATEEN-PLAINTEXT]]" in t:
            snippet = t.split("]]", 1)[1].strip()
            self.plaintext.append(snippet)
            self.log(f"   ✓ DECRYPTED (hook): {snippet[:200]}")

    async def _read_dom(self, page):
        try:
            self.dom = await page.evaluate(r"""() => {
                const v = document.querySelector('video');
                const a = document.querySelector('audio');
                const f = document.querySelector('iframe');
                const eps = [...document.querySelectorAll('a[href*="/watch/"]')]
                    .map(e => ({href: e.getAttribute('href'),
                                t: (e.textContent||'').trim().slice(0,60)}))
                    .slice(0, 60);
                return {
                    title: document.title,
                    video_src: v ? (v.currentSrc || v.src || '') : '',
                    audio_src: a ? (a.currentSrc || a.src || '') : '',
                    iframe_src: f ? (f.getAttribute('src')||'') : '',
                    links: eps
                };
            }""")
        except Exception as e:
            self.log(f"   ! DOM read failed: {e}")

    def _report(self):
        self.log("\n================ RESULT ================")
        d = self.dom
        self.log(f"page title : {d.get('title','')}")
        self.log(f"API calls  : {len(self.api_hits)} "
                 f"({sum(1 for _, iv in self.api_hits if iv)} encrypted)")
        for src_name in ("video_src", "audio_src", "iframe_src"):
            if d.get(src_name):
                self.log(f"{src_name:10s}: {d[src_name][:160]}")
        if self.media_hits:
            self.log(f"\nPLAYABLE media captured ({len(self.media_hits)}):")
            for m in self.media_hits:
                kind = "HLS" if ".m3u8" in m.lower() else (
                    "audio" if re.search(r"\.(mp3|m4a|aac)", m, re.I) else "file")
                self.log(f"   [{kind}] {m}")
        if self.embed_hits:
            self.log(f"\nEMBED hosts (need a 2nd hop): {len(self.embed_hits)}")
            for e in self.embed_hits:
                self.log(f"   {e}")
        if self.plaintext:
            self.log(f"\nDECRYPTED JSON snippets ({len(self.plaintext)}): "
                     f"key/decrypt is reproducible -> pure-HTTP resolver viable")
        # verdict
        if self.media_hits and any(".m3u8" in m or ".mp4" in m for m in self.media_hits):
            v = "EASY  — direct stream captured, one hop."
        elif self.media_hits:
            v = "EASY/MEDIUM — direct media (audio/other) captured."
        elif self.embed_hits:
            v = "MEDIUM — plays via an embed host; needs a second extraction hop."
        elif self.plaintext:
            v = "MEDIUM — API decryptable via hook; parse plaintext for the source."
        else:
            v = "HARD — nothing played; encryption/DRM barrier not cleared."
        self.log(f"\nVERDICT: {v}")
        self.log("========================================")
        self.status("done")


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Carateen Probe — how hard is extraction?")
        self.geometry("860x640"); self.minsize(720, 520)
        self.q = queue.Queue(); self.stop = threading.Event(); self.worker = None
        self._ui(); self.after(120, self._poll)

    def _ui(self):
        pad = dict(padx=8, pady=4)
        top = ttk.LabelFrame(self, text="Paste a carateen.tv link (watch/<id>, a slug, /music, or just an id)")
        top.pack(fill="x", **pad)
        row = ttk.Frame(top); row.pack(fill="x", padx=8, pady=6)
        self.url = tk.StringVar(value="https://carateen.tv/watch/91")
        ttk.Entry(row, textvariable=self.url).pack(side="left", fill="x", expand=True)
        self.go = ttk.Button(row, text="Probe", command=self._start); self.go.pack(side="left", padx=6)

        opt = ttk.Frame(top); opt.pack(fill="x", padx=8, pady=(0, 6))
        self.headless = tk.BooleanVar(value=False)
        ttk.Checkbutton(opt, text="Headless (uncheck to watch it)", variable=self.headless).pack(side="left")
        ttk.Label(opt, text="Settle seconds:").pack(side="left", padx=(16, 4))
        self.settle = tk.IntVar(value=12)
        ttk.Spinbox(opt, from_=4, to=60, width=5, textvariable=self.settle).pack(side="left")
        self.status = tk.StringVar(value="Idle")
        ttk.Label(opt, textvariable=self.status).pack(side="right")

        logf = ttk.LabelFrame(self, text="Log"); logf.pack(fill="both", expand=True, **pad)
        self.txt = tk.Text(logf, height=22, wrap="word", state="disabled")
        self.txt.pack(side="left", fill="both", expand=True, padx=(6, 0), pady=6)
        sb = ttk.Scrollbar(logf, command=self.txt.yview); sb.pack(side="right", fill="y", pady=6)
        self.txt.config(yscrollcommand=sb.set)

    def _append(self, t):
        self.txt.config(state="normal"); self.txt.insert("end", t + "\n")
        self.txt.see("end"); self.txt.config(state="disabled")

    def _start(self):
        if self.worker and self.worker.is_alive():
            return
        cfg = {"url": self.url.get(), "headless": bool(self.headless.get()),
               "settle": int(self.settle.get())}
        self.stop.clear()
        self.txt.config(state="normal"); self.txt.delete("1.0", "end"); self.txt.config(state="disabled")
        self._append("--- starting probe ---")
        self.worker = threading.Thread(target=Probe(cfg, self.q, self.stop).run, daemon=True)
        self.worker.start(); self.go.config(state="disabled")

    def _poll(self):
        try:
            while True:
                kind, payload = self.q.get_nowait()
                if kind == "log": self._append(payload)
                elif kind == "status": self.status.set(payload)
                elif kind == "error": messagebox.showerror("Error", payload)
                elif kind == "done": self.go.config(state="normal")
        except queue.Empty:
            pass
        self.after(120, self._poll)


if __name__ == "__main__":
    App().mainloop()

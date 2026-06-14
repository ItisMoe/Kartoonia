/* ============================================================
   Kartoonia — kids TV streaming app
   • Home / Browse (TV Shows · Movies · My List) / Detail / Player
   • Search: bilingual keyboard, voice input, filter chips
   • Settings: language + playback prefs
   • Geometric D-pad (spatial) focus engine — arrow keys + remote
   ============================================================ */
(function () {
  "use strict";

  // ---------- icons ----------
  const I = {
    play: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
    check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7"/></svg>',
    info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><circle cx="12" cy="7.5" r="1.2" fill="currentColor" stroke="none"/></svg>',
    search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>',
    mic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
    gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M19.4 13.5a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-2.7 1.1V21a2 2 0 0 1-4 0v-.1a1.6 1.6 0 0 0-2.7-1.1l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0-1.1-2.7H4a2 2 0 0 1 0-4h.1a1.6 1.6 0 0 0 1.1-2.7l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3 1.6 1.6 0 0 0 1-1.5V4a2 2 0 0 1 4 0v.1a1.6 1.6 0 0 0 2.7 1.1l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8 1.6 1.6 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z"/></svg>',
    film: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M7 4v16M17 4v16M3 9h4M17 9h4M3 15h4M17 15h4"/></svg>',
    back10: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M11 7L6 11l5 4"/><path d="M6 11h8a5 5 0 0 1 0 10h-3"/></svg>',
    fwd10: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M13 7l5 4-5 4"/><path d="M18 11h-8a5 5 0 0 0 0 10h3"/></svg>',
    pause: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>',
    cc: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="M9 10.5a2 2 0 1 0 0 3M16 10.5a2 2 0 1 0 0 3"/></svg>',
    next: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 5v14l9-7zM16 5h2.5v14H16z"/></svg>',
    del: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 6H8L3 12l5 6h13a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1z"/><path d="M17 9.5l-5 5M12 9.5l5 5"/></svg>',
    backArrow: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 6l-6 6 6 6M4 12h16"/></svg>',
    heart: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20s-7-4.5-9.5-9A4.5 4.5 0 0 1 12 6a4.5 4.5 0 0 1 9.5 5c-2.5 4.5-9.5 9-9.5 9z"/></svg>',
    trailer: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M10 8.5l5.5 3.5L10 15.5z" fill="currentColor" stroke="none"/></svg>',
    server: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/></svg>',
    close: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    chevron: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg>',
  };

  // ---------- state ----------
  let savedInit = [];
  try { savedInit = JSON.parse(localStorage.getItem("kt_saved") || "[]"); } catch (e) { savedInit = []; }
  const state = {
    lang: localStorage.getItem("kt_lang") || "en",
    screen: "home",
    stack: [],
    detailShow: null,
    playerShow: null,
    browseKind: "tv",
    browseLetter: null,
    alphaScript: "en",
    server: "s1",
    query: "",
    kbScript: null,        // 'en' | 'ar' (independent of app language)
    filter: "all",
    playing: true,
    progress: 0.27,
    saved: new Set(savedInit.length ? savedInit : ["falcon", "lulu"]),
    prefs: {
      motion: localStorage.getItem("kt_motion") || "off",
      autoplay: localStorage.getItem("kt_autoplay") || "on",
      subtitles: localStorage.getItem("kt_subs") || "off",
    },
  };
  const T = () => window.STRINGS[state.lang];
  const isRTL = () => state.lang === "ar";
  const title = (s) => s[state.lang] || s.en;
  const syn = (s) => state.lang === "ar" ? s.synAr : s.synEn;
  const genre = (s) => state.lang === "ar" ? s.genreAr : s.genreEn;
  const CAT = () => window.CATALOG;

  // ---------- helpers ----------
  const el = (tag, cls, html) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html != null) e.innerHTML = html;
    return e;
  };
  const bigBg = (s) =>
    `radial-gradient(58% 80% at 72% 26%, ${s.motif}66, transparent 60%),` +
    `radial-gradient(40% 60% at 20% 80%, ${s.g1}55, transparent 60%),` +
    `linear-gradient(135deg, ${s.g1}, ${s.g2})`;

  function posterArt(s) {
    return `
      <div class="poster-art" style="background:linear-gradient(150deg, ${s.g1}, ${s.g2})">
        <div class="ring2"></div>
        <div class="blob" style="background:${s.motif}"></div>
        <div class="blob b2" style="background:${s.g1}"></div>
      </div>`;
  }

  function resumeLabel(s) {
    const t = T();
    if (s.type === "movie") {
      const left = Math.max(1, Math.round(s.mins * (1 - (s.progress || 0))));
      return `${t.movie} · ${left} ${t.minutes} ${t.left}`;
    }
    const totalEp = Math.min(s.episodes, s.episodes);
    const ep = Math.min(totalEp, Math.max(1, Math.round((s.progress || 0) * Math.min(s.episodes, 12)) || 1));
    return `${t.seasonShort}1 · ${t.epShort}${ep}`;
  }
  function card(s, opts) {
    opts = opts || {};
    const c = el("div", "card focusable" + (opts.wide ? " wide" : "") + (opts.progress ? " has-progress" : "") + (opts.resume ? " has-caption" : ""));
    c.dataset.action = opts.play ? "play" : "open";
    c.dataset.show = s.id;
    let inner = `<div class="poster">
      ${posterArt(s)}
      <div class="poster-scrim"></div>
      <div class="poster-badge">${s.age}+</div>`;
    if (s.type === "movie") inner += `<div class="poster-tag"><span class="ti">${I.film}</span>${T().movie}</div>`;
    inner += `<div class="poster-title">${title(s)}</div>`;
    if (opts.resume) inner += `<div class="poster-caption">${resumeLabel(s)}</div>`;
    if (opts.progress) inner += `<div class="poster-progress"><i style="width:${Math.round(opts.progress * 100)}%"></i></div>`;
    inner += `<div class="quickplay">${I.play}</div><div class="card-ring"></div></div>`;
    c.innerHTML = inner;
    return c;
  }

  // landscape backdrop card (shows the show's backdrop art, not the poster)
  function cardBackdrop(s) {
    const c = el("div", "card backdrop-card focusable");
    c.dataset.action = "open"; c.dataset.show = s.id;
    c.innerHTML = `<div class="poster bd">
        <div class="bd-art" style="background:${bigBg(s)}"></div>
        <div class="bd-scrim"></div>
        <div class="poster-badge">${s.age}+</div>
        ${s.type === "movie" ? `<div class="poster-tag"><span class="ti">${I.film}</span>${T().movie}</div>` : ""}
        <div class="bd-info"><div class="bd-title">${title(s)}</div><div class="bd-genre">${genre(s)}</div></div>
        <div class="quickplay">${I.play}</div><div class="card-ring"></div>
      </div>`;
    return c;
  }

  // Top-10 style card: giant rank numeral beside a poster
  function cardTop10(s, rank) {
    const c = el("div", "card top10-card focusable");
    c.dataset.action = "open"; c.dataset.show = s.id;
    c.innerHTML = `<div class="t10-rank">${rank}</div>
      <div class="poster t10-poster">
        ${posterArt(s)}
        <div class="poster-scrim"></div>
        <div class="poster-badge">${s.age}+</div>
        <div class="poster-title">${title(s)}</div>
        <div class="quickplay">${I.play}</div><div class="card-ring"></div>
      </div>`;
    return c;
  }

  function pill(cls, icon, label, action, data) {
    const b = el("button", "pill focusable " + cls);
    b.dataset.action = action;
    if (data) Object.assign(b.dataset, data);
    b.innerHTML = (icon ? `<span class="ico">${icon}</span>` : "") + `<span>${label}</span>`;
    return b;
  }

  // ============================================================
  //  TOP BAR
  // ============================================================
  function renderTop() {
    const bar = document.querySelector(".topbar");
    const t = T();
    bar.innerHTML = `
      <div class="brand"><span class="logo"></span><span class="wordmark"><b>${t.brandA}</b><span class="accent">${t.brandB}</span></span></div>
      <div class="nav">
        <div class="nav-item icon-item focusable top-focus" data-action="nav-search" data-nav="search"><span class="ni-ico">${I.search}</span><span>${t.nav_search}</span></div>
        <div class="nav-item focusable top-focus current" data-action="nav-home" data-nav="home">${t.nav_home}</div>
        <div class="nav-item focusable top-focus" data-action="nav-tv" data-nav="tv">${t.nav_tv}</div>
        <div class="nav-item focusable top-focus" data-action="nav-movies" data-nav="movies">${t.nav_movies}</div>
        <div class="nav-item focusable top-focus" data-action="nav-mylist" data-nav="mylist">${t.nav_mylist}</div>
      </div>
      <div class="spacer"></div>
      <div class="right">
        <div class="settings-btn focusable top-focus" data-action="nav-settings" title="${t.settings}"><span class="gear">${I.gear}</span></div>
      </div>`;
  }
  function setNavCurrent(nav) {
    document.querySelectorAll(".nav-item").forEach(n => n.classList.toggle("current", n.dataset.nav === nav));
  }

  // ============================================================
  //  HOME
  // ============================================================
  const ROWS = [
    { key: "continue", titleKey: "row_continue", wide: true, prog: true },
    { key: "popular", titleKey: "row_popular" },
    { kind: "top10", titleKey: "topten" },
    { key: "movies", titleKey: "spotlight", kind: "backdrop" },
    { key: "new", titleKey: "row_new" },
    { key: "adventure", titleKey: "row_adventure" },
    { key: "learn", titleKey: "row_learn" },
    { key: "bedtime", titleKey: "row_bedtime" },
  ];
  function topTen() {
    const seen = new Set(), out = [];
    ["popular", "new", "adventure"].forEach(k => CAT().forEach(s => { if (s.rows.includes(k) && !seen.has(s.id)) { seen.add(s.id); out.push(s); } }));
    CAT().forEach(s => { if (!seen.has(s.id)) { seen.add(s.id); out.push(s); } });
    return out.slice(0, 10);
  }

  const FEATURED = ["falcon", "salma", "lantern", "layla", "space"];
  let heroIndex = 0, heroTimer = null;
  function heroList() { return FEATURED.map(id => CAT().find(s => s.id === id)).filter(Boolean); }
  function setHeroSlide(i, instant) {
    const hero = document.querySelector("#home .hero-carousel");
    if (!hero) return;
    const list = heroList();
    heroIndex = (i + list.length) % list.length;
    const s = list[heroIndex];
    const t = T();
    const layers = hero.querySelectorAll(".hero-bg.layer");
    const onLayer = hero.querySelector(".hero-bg.layer.is-on") || layers[0];
    const offLayer = [...layers].find(l => l !== onLayer) || layers[1];
    offLayer.style.background = bigBg(s);
    if (instant) { onLayer.style.background = bigBg(s); }
    else { onLayer.classList.remove("is-on"); offLayer.classList.add("is-on"); }
    const meta = s.type === "movie"
      ? `<span class="age-badge">${s.age}+</span><span>${s.year}</span><span>•</span><span>${genre(s)}</span><span>•</span><span>${t.movie}</span>`
      : `<span class="age-badge">${s.age}+</span><span>${s.year}</span><span>•</span><span>${genre(s)}</span><span>•</span><span>${s.seasons} ${t.season}${s.seasons > 1 ? "s" : ""}</span>`;
    const c = hero.querySelector(".hero-content");
    const fill = () => {
      c.innerHTML = `
      <div class="hero-kicker"><span class="dot"></span>${t.featured}</div>
      <div class="hero-title">${title(s)}</div>
      <div class="hero-meta">${meta}</div>
      <div class="hero-syn">${syn(s)}</div>
      <div class="hero-actions"></div>`;
      const ha = c.querySelector(".hero-actions");
      ha.appendChild(pill("primary", I.play, t.watchNow, "play", { show: s.id }));
      ha.appendChild(pill("", I.info, t.moreInfo, "open", { show: s.id }));
      ha.appendChild(listPill(s));
      setTimeout(() => c.classList.remove("swapping"), 30);
    };
    if (instant) { c.classList.remove("swapping"); fill(); }
    else { c.classList.add("swapping"); setTimeout(fill, 280); }
    hero.querySelectorAll(".hero-dot").forEach((d, di) => d.classList.toggle("on", di === heroIndex));
  }
  function startHeroTimer() {
    stopHeroTimer();
    if (state.prefs.autoplay === "off") return;
    heroTimer = setInterval(() => {
      if (state.screen !== "home") return;
      const f = document.querySelector(".focusable.focused");
      if (f && f.closest(".hero-carousel")) return;
      setHeroSlide(heroIndex + 1);
    }, 6500);
  }
  function stopHeroTimer() { clearInterval(heroTimer); heroTimer = null; }

  function renderHome() {
    const scr = document.querySelector("#home .home-scroll");
    scr.style.transform = "translateY(0)";
    scr.innerHTML = "";
    const t = T();

    const hero = el("div", "hero hero-carousel");
    hero.innerHTML = `
      <div class="hero-bg layer is-on"></div>
      <div class="hero-bg layer"></div>
      <div class="hero-content"></div>
      <div class="hero-dots"></div>`;
    scr.appendChild(hero);
    const dots = hero.querySelector(".hero-dots");
    heroList().forEach((s, i) => {
      const d = el("button", "hero-dot focusable", "");
      d.dataset.action = "hero-dot"; d.dataset.i = i;
      d.title = title(s);
      dots.appendChild(d);
    });
    setHeroSlide(0, true);
    startHeroTimer();

    const wrap = el("div", "rows-wrap");
    ROWS.forEach(def => {
      let shows;
      if (def.kind === "top10") shows = topTen();
      else if (def.key === "continue") shows = CAT().filter(s => s.progress > 0);
      else shows = CAT().filter(s => s.rows.includes(def.key));
      if (!shows.length) return;
      const row = el("div", "row" + (def.kind === "top10" ? " row-top10" : "") + (def.kind === "backdrop" ? " row-backdrop" : ""));
      row.innerHTML = `<div class="row-head"><span class="row-title">${t[def.titleKey]}</span>${def.kind === "top10" ? '<span class="top10-badge">TOP 10</span>' : `<span class="row-count">${shows.length}</span>`}</div>`;
      const rail = el("div", "rail");
      if (def.kind === "top10") shows.forEach((s, i) => rail.appendChild(cardTop10(s, i + 1)));
      else if (def.kind === "backdrop") shows.forEach(s => rail.appendChild(cardBackdrop(s)));
      else shows.forEach(s => rail.appendChild(card(s, { wide: def.wide, progress: def.prog ? (s.progress || 0.2) : 0, play: def.key === "continue", resume: def.key === "continue" })));
      row.appendChild(rail);
      wrap.appendChild(row);
    });
    scr.appendChild(wrap);
  }

  function listPill(s) {
    const inList = state.saved.has(s.id);
    return pill(inList ? "in-list" : "", inList ? I.check : I.plus, inList ? T().inList : T().myList, "toggle-list", { show: s.id });
  }

  // ============================================================
  //  BROWSE (TV Shows / Movies / My List)
  // ============================================================
  function renderBrowse(kind) {
    state.browseKind = kind;
    const b = document.querySelector("#browse");
    const t = T();
    let items, titleStr;
    if (kind === "movies") { items = CAT().filter(s => s.type === "movie"); titleStr = t.browse_movies; }
    else if (kind === "mylist") { items = CAT().filter(s => state.saved.has(s.id)); titleStr = t.browse_mylist; }
    else { items = CAT().filter(s => s.type === "series"); titleStr = t.browse_tv; }

    if (kind === "mylist") {
      b.innerHTML = `<div class="browse-scroll vscroll">
          <div class="browse-head"><h2>${titleStr}</h2><span class="browse-count">${items.length}</span></div>
          <div class="browse-grid ${items.length ? "" : "is-empty"}"></div>
        </div>`;
      const grid = b.querySelector(".browse-grid");
      if (!items.length) grid.appendChild(el("div", "browse-empty", `<div class="ghost">${I.heart}</div><p>${t.mylist_empty}</p>`));
      else items.forEach(s => grid.appendChild(card(s)));
      return;
    }

    b.innerHTML = `<div class="browse-scroll vscroll">
        <div class="browse-head"><h2>${titleStr}</h2><span class="browse-count">${items.length}</span></div>
        <div class="alpha-bar"></div>
        <div class="browse-body"></div>
      </div>`;
    renderAlpha(b, items);
    renderBrowseBody(b, items);
  }

  function firstLetterFor(s, script) {
    let ch = ((script === "ar" ? s.ar : s.en).trim()[0] || "");
    if (script === "ar") return ch.replace(/[آأإٱ]/, "ا").replace(/ى/, "ي").replace(/ة/, "ه");
    return ch.toUpperCase();
  }
  function renderAlpha(b, items) {
    const t = T();
    const bar = b.querySelector(".alpha-bar");
    const present = new Set(items.map(s => firstLetterFor(s, state.alphaScript)));
    const tog = el("div", "alpha-script");
    ["en", "ar"].forEach(sc => {
      const tb = el("button", "alpha-tog focusable" + (state.alphaScript === sc ? " sel" : ""), sc === "en" ? t.kbLatin : t.kbArabic);
      tb.dataset.action = "alpha-script"; tb.dataset.v = sc;
      tog.appendChild(tb);
    });
    bar.appendChild(tog);
    const all = el("button", "alpha all focusable" + (state.browseLetter == null ? " sel" : ""), t.alpha_all);
    all.dataset.action = "alpha"; all.dataset.v = "";
    bar.appendChild(all);
    (state.alphaScript === "ar" ? ALPHA_AR : ALPHA_EN).forEach(L => {
      const has = present.has(L);
      const c = el("button", "alpha focusable" + (has ? "" : " disabled") + (state.browseLetter === L ? " sel" : ""), L);
      c.dataset.action = "alpha"; c.dataset.v = L;
      bar.appendChild(c);
    });
  }

  function renderBrowseBody(b, items) {
    const t = T();
    const body = b.querySelector(".browse-body");
    body.innerHTML = "";
    if (state.browseLetter) {
      const matched = items.filter(s => firstLetterFor(s, state.alphaScript) === state.browseLetter);
      const grid = el("div", "browse-grid");
      matched.forEach(s => grid.appendChild(card(s)));
      body.appendChild(grid);
      return;
    }
    CATS.forEach(c => {
      const list = items.filter(c.match);
      if (!list.length) return;
      const row = el("div", "row");
      row.innerHTML = `<div class="row-head"><span class="row-title">${t["cat_" + c.key]}</span><span class="row-count">${list.length}</span></div>`;
      const rail = el("div", "rail");
      list.forEach(s => rail.appendChild(card(s)));
      row.appendChild(rail);
      body.appendChild(row);
    });
  }

  // ============================================================
  //  DETAIL
  // ============================================================
  function renderDetail(s) {
    state.detailShow = s;
    const d = document.querySelector("#detail");
    const t = T();
    const isMovie = s.type === "movie";

    let metaChips = `<span class="age-badge">${s.age}+</span><span>${s.year}</span>`;
    if (isMovie) {
      metaChips += `<span class="chiplet type-chip"><span class="ti">${I.film}</span>${t.movie}</span><span class="chiplet">${s.mins} ${t.minutes}</span>`;
    } else {
      metaChips += `<span class="chiplet">${s.seasons} ${t.season}${s.seasons > 1 ? "s" : ""}</span><span class="chiplet">${s.episodes} ${t.episodes}</span><span class="chiplet">${s.mins} ${t.minutes}</span>`;
    }

    d.innerHTML = `
      <div class="detail-bg" style="background:${bigBg(s)}"></div>
      <div class="detail-content">
        <div class="detail-head">
          <div class="hero-kicker"><span class="dot"></span>${genre(s).toUpperCase()}</div>
          <div class="detail-title">${title(s)}</div>
          <div class="detail-meta">${metaChips}</div>
          <div class="detail-syn">${syn(s)}</div>
          <div class="detail-actions"></div>
        </div>
        <div class="episodes-block">
          <div class="episodes-head"><h3>${isMovie ? t.row_movies : t.episodes}</h3>${isMovie ? "" : `<span class="season-tag">${t.season} 1</span>`}</div>
          <div class="ep-rail"></div>
        </div>
      </div>`;

    const da = d.querySelector(".detail-actions");
    const resume = s.progress > 0;
    da.appendChild(pill("primary", I.play, resume ? t.resume : t.play, "play", { show: s.id }));
    da.appendChild(pill("", I.trailer, t.trailer, "trailer", { show: s.id }));
    da.appendChild(listPill(s));

    const er = d.querySelector(".ep-rail");
    if (isMovie) {
      er.classList.add("like-rail");
      CAT().filter(x => x.id !== s.id && x.type === "movie").slice(0, 8).forEach(x => er.appendChild(card(x)));
    } else {
      const epTitlesEn = ["The Big Start", "A New Friend", "Lost & Found", "The Sky Race", "Secret Door", "Storm Day", "The Great Plan", "Home at Last"];
      const epTitlesAr = ["البداية الكبرى", "صديق جديد", "ضائع وموجود", "سباق السماء", "الباب السري", "يوم العاصفة", "الخطة الكبرى", "العودة للبيت"];
      const n = Math.min(8, s.episodes);
      for (let i = 0; i < n; i++) {
        const ep = el("div", "ep focusable");
        ep.dataset.action = "play"; ep.dataset.show = s.id;
        ep.innerHTML = `
          <div class="ep-thumb" style="background:${bigBg(s)}"><span class="ep-num">${t.epShort}${i + 1}</span></div>
          <div class="ep-body"><h4>${state.lang === "ar" ? epTitlesAr[i] : epTitlesEn[i]}</h4><p>${s.mins} ${t.minutes} • ${t.season} 1</p></div>`;
        er.appendChild(ep);
      }
    }
  }

  // ============================================================
  //  PLAYER
  // ============================================================
  let controlsTimer = null;
  function renderPlayer(s) {
    state.playerShow = s;
    state.playing = true;
    state.progress = s.progress > 0 ? s.progress : 0.08;
    const p = document.querySelector("#player");
    const t = T();
    const sub = s.type === "movie" ? t.movie : `${t.season} 1 • ${t.epShort}1`;
    p.innerHTML = `
      <div class="player-stage" style="background:${bigBg(s)}"></div>
      <div class="player-ui">
        <div class="player-top">
          <button class="ctrl focusable" data-action="back" title="back">${I.backArrow}</button>
          <div class="pt-meta"><div class="pt-title">${title(s)}</div><div class="pt-ep">${sub}</div></div>
          <span class="pt-spacer"></span>
          <div class="pt-server">${t.nowPlaying} <b>${serverName(state.server)}</b></div>
        </div>
        <div class="player-bottom">
          <div class="scrub">
            <span class="cur">0:00</span>
            <div class="scrub-track focusable" data-action="scrub"><div class="scrub-fill"></div><div class="scrub-knob"></div></div>
            <span class="dur">${s.mins}:00</span>
          </div>
          <div class="player-controls">
            <button class="ctrl focusable" data-action="pctrl" data-c="back10">${I.back10}</button>
            <button class="ctrl lg focusable" data-action="pctrl" data-c="playpause">${I.pause}</button>
            <button class="ctrl focusable" data-action="pctrl" data-c="fwd10">${I.fwd10}</button>
            <span class="gap"></span>
            <button class="ctrl text focusable ${state.prefs.subtitles === "on" ? "focused-cc" : ""}" data-action="pctrl" data-c="cc">${I.cc}<span>CC</span></button>
            <button class="ctrl text focusable" data-action="pctrl" data-c="server">${I.server}<span>${t.server}</span></button>
          </div>
        </div>
      </div>`;
    updateScrub();
  }
  function updateScrub() {
    const p = document.querySelector("#player");
    if (!p || !state.playerShow) return;
    const fill = p.querySelector(".scrub-fill");
    const knob = p.querySelector(".scrub-knob");
    if (fill) fill.style.width = (state.progress * 100) + "%";
    if (knob) knob.style.left = (state.progress * 100) + "%";
    const cur = p.querySelector(".cur");
    if (cur) {
      const total = state.playerShow.mins * 60;
      const c = Math.round(total * state.progress);
      cur.textContent = Math.floor(c / 60) + ":" + String(c % 60).padStart(2, "0");
    }
  }
  function flashControls() {
    const ui = document.querySelector("#player .player-ui");
    if (!ui) return;
    ui.classList.remove("hidden");
    clearTimeout(controlsTimer);
    controlsTimer = setTimeout(() => {
      if (state.screen === "player" && state.playing) ui.classList.add("hidden");
    }, 4200);
  }

  // ============================================================
  //  SEARCH
  // ============================================================
  const KB_EN = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".split("");
  const KB_AR = "ابتثجحخدذرزسشصضطظعغفقكلمنهوي".split("");
  const FILTERS = ["all", "tv", "movies"];
  const ALPHA_EN = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("");
  const ALPHA_AR = "ابتثجحخدذرزسشصضطظعغفقكلمنهوي".split("");
  const CATS = [
    { key: "new", match: s => s.year >= 2025 },
    { key: "adventure", match: s => /Adventure/i.test(s.genreEn) },
    { key: "action", match: s => /Action|Superhero/i.test(s.genreEn) },
    { key: "comedy", match: s => /Comedy/i.test(s.genreEn) },
    { key: "fantasy", match: s => /Fantasy|Sci-Fi/i.test(s.genreEn) },
    { key: "preschool", match: s => s.age <= 4 },
    { key: "bedtime", match: s => /Bedtime/i.test(s.genreEn) },
    { key: "classics", match: s => s.year <= 2024 },
  ];
  const SERVERS = [
    { id: "s1", q: "1080p", tag: "HD" },
    { id: "s2", q: "720p", tag: "HD" },
    { id: "s3", q: "480p", tag: "SD" },
    { id: "s4", q: "Auto", tag: "AUTO" },
  ];
  const DEFAULT_TRAILER = "aqz-KE-bpKQ";
  const firstLetter = s => { const ch = (title(s).trim()[0] || ""); return isRTL() ? ch : ch.toUpperCase(); };
  const serverName = id => { const i = SERVERS.findIndex(x => x.id === id); return `${T().server} ${i + 1}`; };

  function renderSearch() {
    if (!state.kbScript) state.kbScript = state.lang;
    const s = document.querySelector("#search");
    const t = T();
    s.innerHTML = `
      <div class="search-layout">
        <div class="kb-side">
          <div class="search-field-row">
            <div class="search-field"><span class="s-ico">${I.search}</span><span class="s-text ${state.query ? "" : "empty"}"></span></div>
            <button class="mic-btn focusable" data-action="voice" title="${t.voice}">${I.mic}</button>
          </div>
          <div class="kb-toolbar">
            <span class="kb-toolbar-label">${t.kbHint}</span>
            <button class="kb-tog focusable" data-action="kb-script" data-v="en">${t.kbLatin}</button>
            <button class="kb-tog focusable" data-action="kb-script" data-v="ar">${t.kbArabic}</button>
          </div>
          <div class="keyboard"></div>
        </div>
        <div class="results-side">
          <div class="filters-row chips"></div>
          <div class="results-title"></div>
          <div class="results-host"></div>
        </div>
      </div>`;
    renderFilters();
    renderKeyboard();
    updateSearchResults();
  }
  function renderKeyboard() {
    const kb = document.querySelector("#search .keyboard");
    if (!kb) return;
    kb.innerHTML = "";
    kb.classList.toggle("ar", state.kbScript === "ar");
    const keys = state.kbScript === "ar" ? KB_AR : KB_EN;
    keys.forEach(k => {
      const b = el("div", "key focusable");
      b.dataset.action = "key"; b.dataset.key = k; b.textContent = k;
      kb.appendChild(b);
    });
    const t = T();
    const space = el("div", "key wide util focusable", t.space);
    space.dataset.action = "key"; space.dataset.key = " ";
    const del = el("div", "key util focusable", I.del);
    del.dataset.action = "key"; del.dataset.key = "__del";
    const clr = el("div", "key wide util focusable", t.clear);
    clr.dataset.action = "key"; clr.dataset.key = "__clear";
    kb.appendChild(space); kb.appendChild(del); kb.appendChild(clr);
    document.querySelectorAll("#search .kb-tog").forEach(b => b.classList.toggle("sel", b.dataset.v === state.kbScript));
  }
  function renderFilters() {
    const row = document.querySelector("#search .filters-row");
    if (!row) return;
    const t = T();
    row.innerHTML = "";
    FILTERS.forEach(f => {
      const c = el("button", "chip focusable" + (state.filter === f ? " sel" : ""), t["filter_" + f]);
      c.dataset.action = "filter"; c.dataset.v = f;
      row.appendChild(c);
    });
  }
  function passFilter(x) {
    const f = state.filter;
    if (f === "tv") return x.type === "series";
    if (f === "movies") return x.type === "movie";
    if (f === "preschool") return x.age <= 4;
    if (f === "bigkids") return x.age >= 6;
    return true;
  }
  function matchShow(x, q) {
    return (x.en + " " + x.ar + " " + x.genreEn + " " + x.genreAr).toLowerCase().includes(q);
  }
  function updateSearchResults() {
    const s = document.querySelector("#search");
    if (!s) return;
    const t = T();
    const txt = s.querySelector(".s-text");
    txt.classList.toggle("empty", !state.query);
    txt.innerHTML = (state.query || t.searchPlaceholder) + (state.query ? '<span class="caret"></span>' : "");
    const host = s.querySelector(".results-host");
    const titleEl = s.querySelector(".results-title");
    const q = state.query.trim().toLowerCase();
    let res;
    if (q) {
      res = CAT().filter(x => matchShow(x, q) && passFilter(x));
      titleEl.textContent = t.resultsFor + " · " + res.length;
    } else {
      res = CAT().filter(x => x.rows.includes("popular") && passFilter(x));
      titleEl.textContent = state.filter === "all" ? t.row_popular : t["filter_" + state.filter];
    }
    if (!res.length) {
      host.innerHTML = "";
      host.appendChild(el("div", "results-empty", `<div class="ghost">${I.search}</div><p>${q ? t.noResults : t.startTyping}</p>`));
      return;
    }
    const grid = el("div", "results-grid");
    res.slice(0, 8).forEach(x => grid.appendChild(card(x)));
    host.innerHTML = ""; host.appendChild(grid);
  }
  function typeKey(k) {
    if (k === "__del") state.query = state.query.slice(0, -1);
    else if (k === "__clear") state.query = "";
    else state.query += k;
    updateSearchResults();
  }

  // ---------- voice ----------
  let voiceRec = null, voiceTimer = null, voiceDone = false;
  function voiceOverlay() {
    let o = document.querySelector("#voice-overlay");
    if (!o) {
      o = el("div", "voice-overlay", "");
      o.id = "voice-overlay";
      document.querySelector(".app").appendChild(o);
    }
    return o;
  }
  function startVoice() {
    const t = T();
    voiceDone = false;
    const o = voiceOverlay();
    o.innerHTML = `
      <div class="voice-card">
        <div class="voice-pulse"><span></span><span></span><span></span>${I.mic}</div>
        <div class="voice-status">${t.voiceListening}</div>
        <div class="voice-hint">${t.voiceSpeak}</div>
      </div>`;
    o.classList.add("show");

    const finish = (text) => {
      if (voiceDone) return;
      voiceDone = true;
      clearTimeout(voiceTimer);
      try { voiceRec && voiceRec.stop(); } catch (e) {}
      o.classList.remove("show");
      if (text) {
        state.query = text;
        state.kbScript = /[\u0600-\u06FF]/.test(text) ? "ar" : "en";
        renderKeyboard();
        updateSearchResults();
        requestAnimationFrame(() => {
          const first = document.querySelector("#search .results-grid .card") || document.querySelector("#search .mic-btn");
          if (first) setFocus(first);
        });
      }
    };

    // try real speech recognition
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    try {
      if (SR) {
        voiceRec = new SR();
        voiceRec.lang = state.kbScript === "ar" ? "ar-SA" : "en-US";
        voiceRec.interimResults = false;
        voiceRec.maxAlternatives = 1;
        voiceRec.onresult = (e) => finish((e.results[0][0].transcript || "").trim());
        voiceRec.onerror = () => {};
        voiceRec.start();
      }
    } catch (e) { voiceRec = null; }

    // graceful demo fallback (also covers no-mic / sandboxed environments)
    voiceTimer = setTimeout(() => {
      if (voiceDone) return;
      const pool = CAT().filter(x => passFilter(x));
      const pick = pool[Math.floor(Math.random() * pool.length)] || CAT()[0];
      const text = state.kbScript === "ar" ? pick.ar : pick.en;
      const status = o.querySelector(".voice-status");
      if (status) status.textContent = text;
      setTimeout(() => finish(text), 650);
    }, 2200);
  }

  // ============================================================
  //  OVERLAYS (trailer · server picker)
  // ============================================================
  function genericOverlay(id, cls) {
    let o = document.querySelector("#" + id);
    if (!o) { o = el("div", cls); o.id = id; document.querySelector(".app").appendChild(o); }
    o.className = cls;
    return o;
  }
  function openTrailer(s) {
    const t = T();
    const o = genericOverlay("trailer-overlay", "media-overlay");
    const vid = s.trailer || DEFAULT_TRAILER;
    o.innerHTML = `
      <div class="trailer-frame">
        <iframe src="https://www.youtube-nocookie.com/embed/${vid}?autoplay=1&rel=0&modestbranding=1&playsinline=1" title="${title(s)}" frameborder="0" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>
      </div>
      <div class="trailer-bar">
        <div class="trailer-title"><span class="tk">${t.trailer}</span> ${title(s)}</div>
        <button class="ov-close focusable" data-action="close-overlay" data-ov="trailer-overlay">${I.close}<span>${t.closeTrailer}</span></button>
      </div>`;
    o.classList.add("show");
    requestAnimationFrame(() => setFocus(o.querySelector(".ov-close")));
  }
  function openServerPanel() {
    const t = T();
    const o = genericOverlay("server-panel", "side-panel");
    o.innerHTML = `
      <div class="sp-card">
        <div class="sp-head"><span class="sp-ico">${I.server}</span><div><h3>${t.servers}</h3><p>${t.chooseServer}</p></div></div>
        <div class="sp-list"></div>
      </div>`;
    const list = o.querySelector(".sp-list");
    SERVERS.forEach((sv, i) => {
      const b = el("button", "sp-opt focusable" + (state.server === sv.id ? " sel" : ""));
      b.dataset.action = "set-server"; b.dataset.v = sv.id;
      b.innerHTML = `<span class="sp-name">${t.server} ${i + 1}</span><span class="sp-meta"><span class="sp-q">${sv.q}</span><span class="sp-tag">${sv.tag}</span><span class="sp-check">${I.check}</span></span>`;
      list.appendChild(b);
    });
    o.classList.add("show");
    requestAnimationFrame(() => setFocus(o.querySelector(".sp-opt.sel") || o.querySelector(".sp-opt")));
  }
  function setServer(id) {
    state.server = id;
    const lbl = document.querySelector("#player .pt-server b");
    if (lbl) lbl.textContent = serverName(id);
    closeOverlay("server-panel");
    requestAnimationFrame(() => { flashControls(); const sv = document.querySelector('#player [data-c="server"]'); if (sv) setFocus(sv); });
  }
  function closeOverlay(id) {
    const o = document.querySelector("#" + id);
    if (o) o.classList.remove("show");
  }
  function anyOverlayOpen() {
    return document.querySelector(".media-overlay.show, .side-panel.show");
  }
  function focusActiveDefault() {
    const scr = document.querySelector(".screen.active");
    const def = scr && scr.querySelector(".focusable");
    if (def) setFocus(def);
  }

  // ============================================================
  //  SETTINGS
  // ============================================================
  function renderSettings() {
    const s = document.querySelector("#settings");
    const t = T();
    const seg = (key, val, optKey) => `<button class="set-opt focusable ${state.prefs[key] === val ? "sel" : ""}" data-action="set-toggle" data-k="${key}" data-v="${val}">${t[optKey]}</button>`;
    s.innerHTML = `
      <div class="settings-panel vscroll">
        <div class="settings-head"><div class="set-gear">${I.gear}</div><div><h2>${t.settings}</h2><p>${t.set_hint}</p></div></div>
        <div class="set-group">
          <div class="set-label">${t.set_language}</div>
          <div class="set-options">
            <button class="set-opt lang-opt focusable ${state.lang === "en" ? "sel" : ""}" data-action="set-lang" data-v="en">English</button>
            <button class="set-opt lang-opt focusable ${state.lang === "ar" ? "sel" : ""}" data-action="set-lang" data-v="ar">العربية</button>
          </div>
        </div>
        <div class="set-group">
          <div class="set-label">${t.set_subtitles}</div>
          <div class="set-options">${seg("subtitles", "on", "on")}${seg("subtitles", "off", "off")}</div>
        </div>
        <div class="set-group">
          <div class="set-label">${t.set_autoplay}</div>
          <div class="set-options">${seg("autoplay", "on", "on")}${seg("autoplay", "off", "off")}</div>
        </div>
        <div class="set-group">
          <div class="set-label">${t.set_motion}</div>
          <div class="set-options">${seg("motion", "on", "on")}${seg("motion", "off", "off")}</div>
        </div>
      </div>`;
  }
  function setPref(k, v) {
    state.prefs[k] = v;
    localStorage.setItem(k === "subtitles" ? "kt_subs" : "kt_" + k, v);
    if (k === "motion") document.querySelector("#tv").classList.toggle("reduce-motion", v === "on");
    renderSettings();
    requestAnimationFrame(() => {
      const sel = document.querySelector(`#settings [data-k="${k}"].sel`);
      if (sel) setFocus(sel);
    });
  }

  // ============================================================
  //  SCREEN SWITCHING
  // ============================================================
  function showScreen(name, opts) {
    opts = opts || {};
    document.querySelectorAll(".screen").forEach(sc => sc.classList.toggle("active", sc.id === name));
    state.screen = name;
    if (name === "home") startHeroTimer(); else stopHeroTimer();
    document.querySelector(".topbar").style.display = name === "player" ? "none" : "flex";
    const hb = document.querySelector(".hintbar"); if (hb) hb.style.opacity = name === "player" ? "0" : "1";

    if (name === "home") setNavCurrent("home");
    else if (name === "browse") { renderBrowse(opts.kind || state.browseKind); setNavCurrent(opts.kind || state.browseKind); }
    else if (name === "detail") renderDetail(opts.show || state.detailShow);
    else if (name === "player") { renderPlayer(opts.show || state.playerShow); flashControls(); }
    else if (name === "search") { setNavCurrent("search"); renderSearch(); }
    else if (name === "settings") renderSettings();

    requestAnimationFrame(() => {
      let def;
      if (name === "home") def = document.querySelector("#home .pill.primary");
      else if (name === "browse") def = document.querySelector("#browse .card");
      else if (name === "detail") def = document.querySelector("#detail .pill.primary");
      else if (name === "player") def = document.querySelector("#player .ctrl.lg");
      else if (name === "search") def = document.querySelector("#search .mic-btn");
      else if (name === "settings") def = document.querySelector("#settings .set-opt");
      setFocus(def);
    });
  }
  function pushScreen(name, opts) {
    state.stack.push({ screen: state.screen, show: state.detailShow, kind: state.browseKind });
    showScreen(name, opts);
  }
  function goBack() {
    const prev = state.stack.pop();
    if (prev) showScreen(prev.screen, { show: prev.show, kind: prev.kind });
    else showScreen("home");
  }
  function resetTo(name, opts) { state.stack = []; showScreen(name, opts); }

  // ============================================================
  //  FOCUS ENGINE (geometric / spatial)
  // ============================================================
  function getFocusables() {
    const ov = anyOverlayOpen();
    if (ov) return [...ov.querySelectorAll(".focusable")];
    const scr = document.querySelector(".screen.active");
    const list = [];
    if (state.screen !== "player") list.push(...document.querySelectorAll(".topbar .focusable"));
    if (scr) list.push(...scr.querySelectorAll(".focusable"));
    return list.filter(e => e.offsetParent !== null || e.closest(".screen.active"));
  }
  function rectOf(e) {
    const r = e.getBoundingClientRect();
    return { cx: r.left + r.width / 2, cy: r.top + r.height / 2, ...r };
  }
  function setFocus(e) {
    if (!e) return;
    const prev = document.querySelector(".focusable.focused");
    if (prev && prev !== e) prev.classList.remove("focused");
    e.classList.add("focused");
    ensureVisible(e);
  }
  function moveFocus(dir) {
    const cur = document.querySelector(".focusable.focused");
    const items = getFocusables();
    if (!items.length) return;
    if (!cur) { setFocus(items[0]); return; }
    const a = rectOf(cur);
    let best = null, bestScore = Infinity;
    for (const it of items) {
      if (it === cur) continue;
      const b = rectOf(it);
      const dx = b.cx - a.cx, dy = b.cy - a.cy;
      let primary, cross, ok;
      if (dir === "right") { ok = dx > 6; primary = dx; cross = Math.abs(dy); }
      else if (dir === "left") { ok = dx < -6; primary = -dx; cross = Math.abs(dy); }
      else if (dir === "down") { ok = dy > 6; primary = dy; cross = Math.abs(dx); }
      else { ok = dy < -6; primary = -dy; cross = Math.abs(dx); }
      if (!ok) continue;
      const score = primary + cross * 2.4;
      if (score < bestScore) { bestScore = score; best = it; }
    }
    if (best) setFocus(best);
  }

  function offsetTopWithin(e, container) {
    let y = 0, n = e;
    while (n && n !== container) { y += n.offsetTop; n = n.offsetParent; }
    return y;
  }
  function ensureVisible(e) {
    const rail = e.closest(".rail, .ep-rail, .filters-row, .alpha-bar");
    if (rail) scrollRail(rail, e);
    if (e.closest("#home")) scrollHomeV(e);
    else if (e.closest("#browse")) scrollGridV("#browse .browse-scroll", e, 300);
    else if (e.closest("#settings")) scrollGridV("#settings .settings-panel", e, 240);
  }
  function scrollRail(rail, child) {
    const kids = [...rail.children];
    if (!kids.length) return;
    const first = kids[0], last = kids[kids.length - 1];
    const pad = 64, innerW = 1920 - pad * 2;
    const contentW = (last.offsetLeft + last.offsetWidth) - first.offsetLeft;
    const maxScroll = Math.max(0, contentW - innerW);
    let t;
    if (!isRTL()) {
      const lead = child.offsetLeft - first.offsetLeft;
      t = -Math.min(lead, maxScroll);
    } else {
      const lead = (first.offsetLeft + first.offsetWidth) - (child.offsetLeft + child.offsetWidth);
      t = Math.min(lead, maxScroll);
    }
    rail.style.transform = `translateX(${t}px)`;
  }
  function scrollHomeV(e) {
    const scr = document.querySelector("#home .home-scroll");
    if (!scr) return;
    const row = e.closest(".row");
    const maxV = Math.max(0, scr.scrollHeight - 1080 + 40);
    let target = 0;
    if (row) target = Math.min(Math.max(0, row.offsetTop - 460), maxV);
    scr.style.transform = `translateY(${-target}px)`;
  }
  function scrollGridV(sel, e, anchor) {
    const scr = document.querySelector(sel);
    if (!scr) return;
    const maxV = Math.max(0, scr.scrollHeight - 1080 + 40);
    const top = offsetTopWithin(e, scr);
    const target = Math.min(Math.max(0, top - anchor), maxV);
    scr.style.transform = `translateY(${-target}px)`;
  }

  // ============================================================
  //  ACTIONS
  // ============================================================
  function activate(e) {
    const a = e.dataset.action;
    const show = e.dataset.show ? CAT().find(s => s.id === e.dataset.show) : null;
    switch (a) {
      case "open": if (show) pushScreen("detail", { show }); break;
      case "play": if (show) pushScreen("player", { show }); break;
      case "nav-home": resetTo("home"); break;
      case "nav-search": resetTo("search"); break;
      case "nav-tv": state.browseLetter = null; resetTo("browse", { kind: "tv" }); break;
      case "nav-movies": state.browseLetter = null; resetTo("browse", { kind: "movies" }); break;
      case "nav-mylist": state.browseLetter = null; resetTo("browse", { kind: "mylist" }); break;
      case "nav-settings": pushScreen("settings"); break;
      case "toggle-list": if (show) toggleList(show, e); break;
      case "trailer": if (show) openTrailer(show); break;
      case "alpha": state.browseLetter = e.dataset.v || null; renderBrowse(state.browseKind); requestAnimationFrame(() => { const sel = document.querySelector("#browse .alpha.sel"); if (sel) setFocus(sel); }); break;
      case "alpha-script": state.alphaScript = e.dataset.v; state.browseLetter = null; renderBrowse(state.browseKind); requestAnimationFrame(() => { const sel = document.querySelector("#browse .alpha-tog.sel"); if (sel) setFocus(sel); }); break;
      case "hero-dot": setHeroSlide(+e.dataset.i); startHeroTimer(); break;
      case "close-overlay": closeOverlay(e.dataset.ov); focusActiveDefault(); break;
      case "set-server": setServer(e.dataset.v); break;
      case "key": typeKey(e.dataset.key); break;
      case "voice": startVoice(); break;
      case "kb-script": state.kbScript = e.dataset.v; renderKeyboard(); break;
      case "filter": state.filter = e.dataset.v; renderFilters(); updateSearchResults(); break;
      case "set-lang": setLang(e.dataset.v); break;
      case "set-toggle": setPref(e.dataset.k, e.dataset.v); break;
      case "back": goBack(); break;
      case "pctrl": playerCtrl(e.dataset.c); break;
      case "scrub": break;
      case "noop": pulse(e); break;
    }
  }
  function toggleList(s, e) {
    if (state.saved.has(s.id)) state.saved.delete(s.id); else state.saved.add(s.id);
    localStorage.setItem("kt_saved", JSON.stringify([...state.saved]));
    // update any list buttons for this show
    document.querySelectorAll(`[data-action="toggle-list"][data-show="${s.id}"]`).forEach(btn => {
      const inList = state.saved.has(s.id);
      btn.classList.toggle("in-list", inList);
      btn.innerHTML = `<span class="ico">${inList ? I.check : I.plus}</span><span>${inList ? T().inList : T().myList}</span>`;
    });
    if (state.screen === "browse" && state.browseKind === "mylist") renderBrowse("mylist");
  }
  function pulse(e) {
    e.animate([{ transform: "scale(1.06)" }, { transform: "scale(0.97)" }, { transform: "scale(1.06)" }], { duration: 240, easing: "ease" });
  }
  function playerCtrl(c) {
    flashControls();
    if (c === "playpause") {
      state.playing = !state.playing;
      const btn = document.querySelector('#player [data-c="playpause"]');
      if (btn) btn.innerHTML = state.playing ? I.pause : I.play;
      if (state.playing) startPlayback(); else stopPlayback();
    } else if (c === "back10") { state.progress = Math.max(0, state.progress - 0.04); updateScrub(); }
    else if (c === "fwd10") { state.progress = Math.min(1, state.progress + 0.04); updateScrub(); }
    else if (c === "cc") { const b = document.querySelector('#player [data-c="cc"]'); if (b) b.classList.toggle("focused-cc"); }
    else if (c === "server") { openServerPanel(); }
  }
  let playTimer = null;
  function startPlayback() {
    stopPlayback();
    playTimer = setInterval(() => {
      if (state.screen !== "player") { stopPlayback(); return; }
      state.progress = Math.min(1, state.progress + 0.0016);
      updateScrub();
      if (state.progress >= 1) stopPlayback();
    }, 200);
  }
  function stopPlayback() { clearInterval(playTimer); playTimer = null; }
  function scrubFromFocus(dir) {
    state.progress = Math.min(1, Math.max(0, state.progress + (dir === "right" ? 0.025 : -0.025)));
    updateScrub(); flashControls();
  }

  // ---------- language ----------
  function setLang(lang) {
    if (lang === state.lang) return;
    state.lang = lang;
    state.kbScript = lang;
    state.browseLetter = null;
    localStorage.setItem("kt_lang", lang);
    applyLang();
    renderTop();
    renderHome();
    renderSettings();
    setNavCurrent("settings" === state.screen ? "" : state.screen);
    requestAnimationFrame(() => {
      const sel = document.querySelector("#settings .lang-opt.sel");
      if (sel) setFocus(sel);
    });
  }
  function applyLang() {
    const tv = document.querySelector("#tv");
    tv.setAttribute("dir", isRTL() ? "rtl" : "ltr");
    tv.setAttribute("lang", state.lang);
    document.documentElement.setAttribute("lang", state.lang);
  }

  // ============================================================
  //  INPUT
  // ============================================================
  function onKey(ev) {
    const k = ev.key;
    const map = { ArrowRight: "right", ArrowLeft: "left", ArrowUp: "up", ArrowDown: "down" };
    if (map[k]) {
      ev.preventDefault();
      const cur = document.querySelector(".focusable.focused");
      if (state.screen === "player" && cur && cur.classList.contains("scrub-track") && (k === "ArrowLeft" || k === "ArrowRight")) {
        scrubFromFocus(map[k]); return;
      }
      if (state.screen === "player") flashControls();
      moveFocus(map[k]);
    } else if (k === "Enter" || k === " ") {
      ev.preventDefault();
      const cur = document.querySelector(".focusable.focused");
      if (cur) activate(cur);
    } else if (k === "Escape" || k === "Backspace") {
      ev.preventDefault();
      const ov = anyOverlayOpen();
      if (ov) { ov.classList.remove("show"); focusActiveDefault(); return; }
      if (document.querySelector("#voice-overlay.show")) { voiceDone = true; document.querySelector("#voice-overlay").classList.remove("show"); return; }
      if (state.screen !== "home") goBack();
    }
  }
  function wireRemote() {
    document.querySelectorAll("[data-remote]").forEach(b => {
      b.addEventListener("click", () => {
        const r = b.dataset.remote;
        if (r === "ok") { const cur = document.querySelector(".focusable.focused"); if (cur) activate(cur); }
        else if (r === "back") { if (state.screen !== "home") goBack(); }
        else if (r === "home") resetTo("home");
        else { if (state.screen === "player") flashControls(); moveFocus(r); }
      });
    });
  }
  document.addEventListener("click", (ev) => {
    const f = ev.target.closest(".focusable");
    if (!f) return;
    setFocus(f);
    activate(f);
  });
  document.addEventListener("mousemove", (ev) => {
    const f = ev.target.closest(".focusable");
    if (f && !f.classList.contains("focused")) {
      if (f.closest(".screen.active") || f.closest(".topbar") || f.closest(".media-overlay, .side-panel, #voice-overlay")) {
        const prev = document.querySelector(".focusable.focused");
        if (prev) prev.classList.remove("focused");
        f.classList.add("focused");
      }
    }
  });

  // ============================================================
  //  SCALING  (absolute-centred, ResizeObserver-driven)
  // ============================================================
  function scaleTV() {
    const tv = document.querySelector("#tv");
    if (!tv) return;
    const s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
    tv.style.transform = `translate(-50%, -50%) scale(${s})`;
  }
  window.addEventListener("resize", scaleTV);
  window.addEventListener("orientationchange", scaleTV);
  if (window.ResizeObserver) {
    try { new ResizeObserver(scaleTV).observe(document.documentElement); } catch (e) {}
  }

  // ============================================================
  //  BOOT
  // ============================================================
  function boot() {
    applyLang();
    if (state.prefs.motion === "on") document.querySelector("#tv").classList.add("reduce-motion");
    renderTop();
    renderHome();
    wireRemote();
    scaleTV();
    requestAnimationFrame(scaleTV);
    setTimeout(scaleTV, 200);
    showScreen("home");
    window.addEventListener("keydown", onKey);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();

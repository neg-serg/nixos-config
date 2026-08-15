// ==UserScript==
// @name         dsh web: hide page header and footer
// @namespace    neg.local
// @version      1.1.0
// @description  Скрывает шапку (заголовок с кнопками) и нижние строки-статусы страницы DeepSeek Harness (127.0.0.1:3080) — в окне не остаётся «двойного navbar»; внизу только адресбар Vivaldi
// @match        http://127.0.0.1:3080/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
  'use strict';
  const HEADER_MARKERS = ['Standard mode', 'subagent', 'background jobs', 'Session log', 'Files', 'Changes'];
  const FOOTER_MARKERS = ['Full access', 'DeepSeek-V4-Flash', 'Cache hit', 'TTFT', 'Tool call', 'LLM '];
  const ALL = HEADER_MARKERS.concat(FOOTER_MARKERS);
  const MAX_ROW_H = 180;
  const TOP_ZONE = 240;
  const BOTTOM_ZONE = 280;

  function rowLike(el, markers) {
    if (!(el instanceof HTMLElement)) return false;
    const r = el.getBoundingClientRect();
    if (!(r.height > 0) || r.height > MAX_ROW_H) return false;
    if (r.width < Math.min(window.innerWidth, 900) * 0.5) return false;
    const t = (el.textContent || '').trim();
    if (t.length < 4 || t.length > 700) return false;
    return markers.some((m) => t.includes(m));
  }

  function hideRow(leaf) {
    let el = leaf;
    for (let i = 0; i < 6; i++) {
      const p = el.parentElement;
      if (p && p !== el && rowLike(p, ALL)) el = p;
      else break;
    }
    el.style.display = 'none';
    return el;
  }

  function run() {
    let count = 0;
    const vh = window.innerHeight || document.documentElement.clientHeight;
    for (const el of document.querySelectorAll('div,section,footer,header,aside')) {
      if (el.style && el.style.display === 'none') continue;
      const r = el.getBoundingClientRect();
      if (r.bottom <= 0 || r.top >= vh) continue;
      const isTop = r.top < TOP_ZONE;
      if (!isTop && !(r.bottom > vh - BOTTOM_ZONE)) continue;
      const markers = isTop ? HEADER_MARKERS : FOOTER_MARKERS;
      if (rowLike(el, markers)) { hideRow(el); count++; }
    }
    if (count) console.log('[hide-dsh-ui] hidden', count);
  }

  run();
  new MutationObserver(run).observe(document.documentElement, { childList: true, subtree: true });
  setInterval(run, 2500);
})();

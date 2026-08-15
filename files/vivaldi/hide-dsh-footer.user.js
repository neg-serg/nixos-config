// ==UserScript==
// @name         dsh web: hide bottom footer rows
// @namespace    neg.local
// @version      1.0.0
// @description  Скрывает нижние строки-статусы страницы DeepSeek Harness (127.0.0.1:3080), чтобы внизу оставался только адресбар Vivaldi
// @match        http://127.0.0.1:3080/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
  'use strict';
  // Маркеры, уникальные для нижних строк футера страницы (модель/доступ и статистика сессии)
  const MARKERS = ['Full access', 'DeepSeek-V4-Flash', 'Cache hit', 'TTFT', 'Tool call', 'LLM '];
  const MAX_ROW_H = 140;
  const BOTTOM_ZONE = 260;

  function isFooterish(el) {
    if (!(el instanceof HTMLElement)) return false;
    const r = el.getBoundingClientRect();
    const vh = window.innerHeight || document.documentElement.clientHeight;
    if (!(r.height > 0) || r.height > MAX_ROW_H) return false;
    if (r.bottom < vh - BOTTOM_ZONE || r.bottom > vh + 8) return false;
    if (r.width < Math.min(vh, 600) * 0.5) return false;
    const t = (el.textContent || '').trim();
    if (t.length < 4 || t.length > 600) return false;
    return MARKERS.some((m) => t.includes(m));
  }

  // Поднимаемся от листа к контейнеру-строке (пока родитель всё ещё "футероподобен")
  function hideRow(leaf) {
    let el = leaf;
    for (let i = 0; i < 5; i++) {
      const p = el.parentElement;
      if (p && isFooterish(p)) el = p;
      else break;
    }
    el.style.display = 'none';
    return el;
  }

  function run() {
    let count = 0;
    const vh = window.innerHeight || document.documentElement.clientHeight;
    const vw = window.innerWidth || document.documentElement.clientWidth;
    // 1) Точечные пробы внизу по центру
    for (const dy of [18, 48, 88, 128]) {
      const els = document.elementsFromPoint(vw / 2, vh - dy);
      for (const el of els) {
        if (el.style && el.style.display === 'none') continue;
        if (isFooterish(el)) { hideRow(el); count++; }
      }
    }
    // 2) Полный проход как страховка
    for (const el of document.querySelectorAll('div,section,footer,aside')) {
      if (el.style && el.style.display === 'none') continue;
      if (isFooterish(el)) { hideRow(el); count++; }
    }
    if (count) console.log('[hide-dsh-footer] hidden', count);
  }

  run();
  new MutationObserver(run).observe(document.documentElement, { childList: true, subtree: true });
  setInterval(run, 2500);
})();

// neg newtab — new tab page for Vivaldi.
//
// Everything is local: no fonts, no analytics, no CDN. The only optional
// network call is open-meteo for the weather chip, and it is skipped entirely
// until a location is configured (see WEATHER below).

"use strict";

// --- configuration ---------------------------------------------------------

const SEARCH_URL = "https://www.google.com/search?q=";

// Replace with your own set; overridable at runtime via the editor (Ctrl+E).
const DEFAULT_LINKS = [
  { title: "GitHub", url: "https://github.com/" },
  { title: "OpenNet", url: "https://opennet.ru/" },
  { title: "Bandcamp", url: "https://bandcamp.com/" },
  { title: "YouTube", url: "https://www.youtube.com/" },
  { title: "Wiki", url: "https://en.wikipedia.org/" },
  { title: "Reddit", url: "https://www.reddit.com/" },
  { title: "NixOS", url: "https://search.nixos.org/packages" },
  { title: "Hyprland", url: "https://wiki.hypr.land/" },
];

// Weather needs coordinates; it stays hidden until they are set:
//   chrome.storage.local.set({ weather: { lat: 55.75, lon: 37.62, label: "Москва" } })
const WEATHER_STORAGE_KEY = "weather";

// --- storage helpers -------------------------------------------------------

function getStored(key) {
  return new Promise((resolve) => {
    try {
      chrome.storage.local.get(key, (data) =>
        resolve(data ? data[key] : undefined),
      );
    } catch {
      resolve(undefined);
    }
  });
}

function setStored(key, value) {
  return new Promise((resolve) => {
    try {
      chrome.storage.local.set({ [key]: value }, resolve);
    } catch {
      resolve();
    }
  });
}

// --- clock -----------------------------------------------------------------

const clockEl = document.getElementById("clock");
const dateEl = document.getElementById("date");
const greetingEl = document.getElementById("greeting");

const timeFmt = new Intl.DateTimeFormat("ru-RU", {
  hour: "2-digit",
  minute: "2-digit",
});
const dateFmt = new Intl.DateTimeFormat("ru-RU", {
  weekday: "long",
  day: "numeric",
  month: "long",
});

function greetingFor(hour) {
  if (hour < 5) return "Доброй ночи";
  if (hour < 12) return "Доброе утро";
  if (hour < 18) return "Добрый день";
  return "Добрый вечер";
}

function tick() {
  const now = new Date();
  clockEl.textContent = timeFmt.format(now);
  dateEl.textContent = dateFmt.format(now);
  greetingEl.textContent = greetingFor(now.getHours());
}

tick();
setInterval(tick, 1000 * 10);

// --- search ----------------------------------------------------------------

const form = document.getElementById("search");
const query = document.getElementById("q");

// Looks like a host (with a dot and a known-ish TLD) or carries a scheme →
// treat it as an address, not a query.
function asUrl(text) {
  const raw = text.trim();
  if (!raw) return null;
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(raw)) return raw;
  if (/^(localhost|[\w-]+(\.[\w-]+)*\.(ru|com|org|net|io|dev|sh|me|tv|cc|de|edu|gov|info|xyz|land|art|fm|ai|app|wiki))\b(\/\S*)?$/i.test(raw)) {
    return "https://" + raw;
  }
  return null;
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const text = query.value.trim();
  if (!text) return;
  const target = asUrl(text) || SEARCH_URL + encodeURIComponent(text);
  location.href = target;
});

// Prefill from chrome://newtab?q=... or an omnibox-like handoff.
const incoming = new URLSearchParams(location.search).get("q");
if (incoming) {
  query.value = incoming;
}

// --- quick links -----------------------------------------------------------

const tilesEl = document.getElementById("tiles");

function faviconUrl(pageUrl) {
  return `chrome-extension://${chrome.runtime.id}/_favicon/?pageUrl=${encodeURIComponent(pageUrl)}&size=64`;
}

function renderTiles(links) {
  tilesEl.replaceChildren();
  for (const { title, url } of links) {
    const a = document.createElement("a");
    a.className = "tile";
    a.href = url;
    a.title = title;

    const icon = document.createElement("span");
    icon.className = "tile-icon";
    icon.textContent = (title || url).trim().charAt(0).toUpperCase();
    if (url.startsWith("http")) {
      // Private favicon endpoint: works offline in Chromium without host
      // permissions and never leaks the site list to a third party.
      const img = new Image(64, 64);
      img.src = faviconUrl(url);
      img.alt = "";
      img.addEventListener("load", () => icon.replaceChildren(img));
    }

    const label = document.createElement("span");
    label.className = "tile-title";
    label.textContent = title || url;

    a.append(icon, label);
    tilesEl.append(a);
  }
}

async function loadLinks() {
  const stored = await getStored("links");
  renderTiles(Array.isArray(stored) && stored.length ? stored : DEFAULT_LINKS);
}

// --- link editor -----------------------------------------------------------

const editor = document.getElementById("editor");
const editorText = document.getElementById("editor-text");

function openEditor() {
  getStored("links").then((stored) => {
    const links = Array.isArray(stored) && stored.length ? stored : DEFAULT_LINKS;
    editorText.value = links.map((l) => `${l.title} | ${l.url}`).join("\n");
    editor.showModal();
  });
}

function parseEditor(text) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const idx = line.lastIndexOf("|");
      if (idx === -1) return { title: line, url: line };
      return {
        title: line.slice(0, idx).trim(),
        url: line.slice(idx + 1).trim(),
      };
    })
    .filter((l) => /^[a-z][a-z0-9+.-]*:\/\//i.test(l.url))
    .slice(0, 24);
}

document.getElementById("edit").addEventListener("click", openEditor);
document.getElementById("editor-cancel").addEventListener("click", () =>
  editor.close(),
);
document.getElementById("editor-reset").addEventListener("click", () => {
  editorText.value = DEFAULT_LINKS.map((l) => `${l.title} | ${l.url}`).join("\n");
});
document.getElementById("editor-save").addEventListener("click", async () => {
  const links = parseEditor(editorText.value);
  if (links.length) {
    await setStored("links", links);
    renderTiles(links);
  }
  editor.close();
});

document.addEventListener("keydown", (event) => {
  const typing = /^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName);
  if (event.ctrlKey && event.key.toLowerCase() === "e" && !typing) {
    event.preventDefault();
    openEditor();
  }
  if (event.key === "Escape" && !editor.open) {
    query.value = "";
    query.blur();
  }
  // Any printable key goes to the search field, like a launcher.
  if (!typing && !editor.open && event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
    query.focus();
  }
});

// --- weather (optional) ----------------------------------------------------

const weatherEl = document.getElementById("weather");

const WMO = {
  0: "Ясно",
  1: "Почти ясно",
  2: "Переменная облачность",
  3: "Пасмурно",
  45: "Туман",
  48: "Изморозь",
  51: "Слабая морось",
  53: "Морось",
  55: "Сильная морось",
  61: "Небольшой дождь",
  63: "Дождь",
  65: "Ливень",
  71: "Небольшой снег",
  73: "Снег",
  75: "Сильный снег",
  80: "Дождевые заряды",
  81: "Ливни",
  82: "Сильные ливни",
  95: "Гроза",
  96: "Гроза с градом",
  99: "Сильная гроза с градом",
};

async function loadWeather() {
  const cfg = await getStored(WEATHER_STORAGE_KEY);
  if (!cfg || typeof cfg.lat !== "number" || typeof cfg.lon !== "number") {
    return; // not configured → chip stays hidden
  }
  const url =
    "https://api.open-meteo.com/v1/forecast?latitude=" +
    cfg.lat +
    "&longitude=" +
    cfg.lon +
    "&current=temperature_2m,weather_code&timezone=auto";
  try {
    const res = await fetch(url);
    if (!res.ok) return;
    const data = await res.json();
    const current = data.current;
    if (!current) return;
    document.getElementById("wx-temp").textContent =
      `${Math.round(current.temperature_2m)}°C`;
    document.getElementById("wx-text").textContent =
      WMO[current.weather_code] || "";
    weatherEl.hidden = false;
  } catch {
    /* offline or blocked — no chip, no error noise */
  }
}

// --- boot ------------------------------------------------------------------

loadLinks();
loadWeather();
query.focus();

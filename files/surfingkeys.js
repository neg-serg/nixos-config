// Surfingkeys configuration
// https://github.com/brookhong/Surfingkeys

// ========== Settings ==========
settings.hintAlign = "left";
settings.hintCharacters = "asdfghjkl";
settings.omnibarSuggestion = true;
settings.omnibarPosition = "bottom";
settings.focusFirstCandidate = true;
settings.scrollStepSize = 120;
settings.smoothScroll = true;
settings.modeAfterYank = "Normal";

// ========== Theme ==========
settings.theme = `
:root {
  --font: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  --font-mono: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  --font-size: 0.875rem;
  --bg: #020202;
  --bg-highlight: #13384f;
  --fg: #f0f1ff;
  --fg-muted: rgba(240, 241, 255, 0.6);
  --accent: #89cdd2;
  --border: #0a3749;
  --hint-bg: #001742;
}

/* Global styles */
body {
  font-family: var(--font);
  font-size: var(--font-size);
}

/* Hints are styled via Hints.style() API - see below */

/* Base theme for UI elements (omnibar, status, etc.) */
.sk_theme {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  background: var(--bg);
  color: var(--fg);
}

/* Omnibar */
#sk_omnibar {
  width: 50%;
  left: 25%;
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  overflow: hidden;
}

#sk_omnibarSearchArea {
  background: var(--bg) !important;
  border-bottom: 1px solid var(--border) !important;
  padding: 8px 12px !important;
  margin: 0 !important;
}

#sk_omnibarSearchArea input {
  font-family: var(--font-mono) !important;
  font-size: var(--font-size) !important;
  font-weight: 600 !important;
  color: var(--fg) !important;
  background: transparent !important;
  caret-color: var(--fg) !important;
}

#sk_omnibarSearchArea .prompt {
  color: var(--accent) !important;
  font-weight: 600 !important;
}

#sk_omnibarSearchArea .separator {
  color: var(--border) !important;
}

#sk_omnibarSearchResult {
  margin: 0 !important;
  max-height: calc(8 * 1.2em);
  overflow-y: auto;
  scrollbar-width: thin;
  scrollbar-color: var(--border) transparent;
}

#sk_omnibarSearchResult > ul {
  padding: 0 !important;
  margin: 0 !important;
}

#sk_omnibarSearchResult li {
  padding: 4px 12px !important;
  margin: 0 !important;
  border-radius: 0 !important;
  background: transparent !important;
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
}

#sk_omnibarSearchResult li.focused {
  background: rgba(19, 56, 79, 0.8) !important;
}

#sk_omnibarSearchResult li .title {
  color: var(--fg) !important;
  font-weight: 600 !important;
}

#sk_omnibarSearchResult li .url {
  color: var(--fg-muted) !important;
  font-size: var(--font-size) !important;
}

/* Status bar / Banner */
#sk_banner {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
  background: var(--bg);
  color: var(--fg);
  border: 1px solid var(--border);
  border-radius: 0;
  box-shadow: none;
  padding: 4px 12px;
}

/* Keystroke help */
#sk_keystroke {
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  padding: 8px !important;
}

#sk_keystroke kbd {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
  color: var(--accent);
  background: var(--hint-bg);
  border: 1px solid var(--border);
  border-radius: 0;
  padding: 2px 4px;
  margin: 2px;
  box-shadow: none;
}

#sk_keystroke .annotation {
  color: var(--fg);
  font-family: var(--font-mono);
}

#sk_keystroke .candidates {
  color: var(--accent) !important;
}

/* Status line */
#sk_status {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
  background: var(--bg);
  color: var(--fg);
  border: 1px solid var(--border);
  border-radius: 0;
  right: 10px !important;
  bottom: 10px !important;
}

#sk_status > span {
  padding: 4px 8px;
}

/* Rich hints */
.expandRichHints {
  animation: none;
}

.collapseRichHints {
  animation: none;
}

/* Visual mode */
#sk_find {
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0 !important;
}

#sk_find input {
  font-family: var(--font-mono) !important;
  font-weight: 600 !important;
  color: var(--fg) !important;
  background: transparent !important;
}

/* Tab switcher (w key) - override gradients */
#sk_tabs {
  background: var(--bg) !important;
}

div.sk_tab {
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
}

div.sk_tab_title {
  color: var(--fg) !important;
}

div.sk_tab_url {
  color: var(--fg-muted) !important;
}

div.sk_tab_hint {
  font-family: var(--font-mono) !important;
  font-weight: 600 !important;
  background: var(--hint-bg) !important;
  color: var(--accent) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
}

/* kbd elements (keybindings display) */
kbd {
  font-family: var(--font-mono) !important;
  background: var(--hint-bg) !important;
  color: var(--accent) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
}

/* Bubble popup (link previews, etc.) */
#sk_bubble {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
}

#sk_bubble * {
  color: var(--fg) !important;
}

/* List item backgrounds (override white/light defaults) */
.sk_theme #sk_omnibarSearchResult > ul > li:nth-child(odd) {
  background: var(--bg) !important;
}

.sk_theme #sk_omnibarSearchResult > ul > li:nth-child(even) {
  background: rgba(10, 55, 73, 0.3) !important;
}

/* Usage/help popup */
#sk_usage {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}

#sk_usage .feature_name {
  color: var(--accent) !important;
}

#sk_usage span.annotation {
  color: var(--fg-muted) !important;
}

/* Editor popup */
#sk_editor {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}

/* Popup */
#sk_popup {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}

/* Rich hints annotations */
.expandRichHints span.annotation {
  color: var(--accent) !important;
}

.expandRichHints kbd > .candidates {
  color: var(--accent) !important;
}
`;
// ========== Hints Styling (Shadow DOM) ==========
// Hints live in a separate Shadow DOM and DON'T inherit settings.theme!
// Must use api.Hints.style() API to override the default yellow gradient.
api.Hints.style(`
  font-family: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.875rem;
  font-weight: 600;
  padding: 2px 4px;
  background: #001742;
  color: #89cdd2;
  border: 1px solid #0a3749;
  border-radius: 0;
  box-shadow: none;
`);

// Style for text/visual mode hints
api.Hints.style(`
  div {
    font-family: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.875rem;
    font-weight: 600;
    padding: 2px 4px;
    background: #001742;
    color: #89cdd2;
    border: 1px solid #0a3749;
    border-radius: 0;
    box-shadow: none;
  }
  div.begin {
    color: #89cdd2;
  }
`, "text");

// ========== Smart Omnibar ==========
// Unmap default bindings first to avoid conflicts
api.unmap('t');
api.unmap('o');
api.unmap('O');
api.unmap('b');
api.unmap('v');

// Smart navigation: opens omnibar for URL/Search input
api.mapkey("t", "Open URL/Search (New Tab)", () => {
  api.Front.openOmnibar({ type: "URLs" });
});

api.mapkey("o", "Open URL/Search (Current Tab)", () => {
  api.Front.openOmnibar({ type: "URLs" });
});

api.mapkey("O", "Open URL/Search (New Tab)", () => {
  api.Front.openOmnibar({ type: "URLs" });
});

// ========== Mappings ==========
// Scroll
api.map('j', 'j');
api.map('k', 'k');

// Large Scroll (Half Page)
api.mapkey('b', 'Scroll half page down', () => {
  api.Normal.scroll("pageDown");
});
api.mapkey('v', 'Scroll half page up', () => {
  api.Normal.scroll("pageUp");
});

// Tabs (unmap default scroll first)
api.unmap('e');  // Default: scroll page up
api.unmap('E');  // Default: scroll page down
api.map('E', 'E');  // Previous tab (keep E as prev tab - it's the default)
api.map('e', 'R');  // Next tab (R is default next tab)
api.mapkey('d', 'Close current tab', function () {
  api.RUNTIME("closeTab");
});
api.map('u', 'X');  // Restore tab
api.map('w', 'T');  // Tab list

// History
api.map('H', 'S');  // Back
api.map('L', 'D');  // Forward

// Open links
api.map('F', 'gf'); // Open link in new tab

// Clipboard
api.map('yy', 'yy');
api.map('yl', 'yl');

// Video speed
api.mapkey(']', 'Increase video speed', function () {
  const video = document.querySelector('video');
  if (video) {
    video.playbackRate += 0.25;
    api.Front.showBanner("Speed: " + video.playbackRate.toFixed(2) + "x");
  }
});
api.mapkey('[', 'Decrease video speed', function () {
  const video = document.querySelector('video');
  if (video) {
    video.playbackRate = Math.max(0.25, video.playbackRate - 0.25);
    api.Front.showBanner("Speed: " + video.playbackRate.toFixed(2) + "x");
  }
});

// Search engines
api.addSearchAlias('g', 'Google', 'https://www.google.com/search?q=');
api.addSearchAlias('d', 'DuckDuckGo', 'https://duckduckgo.com/?q=');
api.addSearchAlias('y', 'YouTube', 'https://www.youtube.com/results?search_query=');
api.addSearchAlias('w', 'Wikipedia', 'https://en.wikipedia.org/wiki/Special:Search?search=');
api.addSearchAlias('gh', 'GitHub', 'https://github.com/search?q=');
api.addSearchAlias('aw', 'Arch Wiki', 'https://wiki.archlinux.org/index.php?search=');
api.addSearchAlias('np', 'npm', 'https://www.npmjs.com/search?q=');

// ========== Quickmarks ==========
const quickmarks = {
  'A': { name: 'ArtStation', url: 'https://magazine.artstation.com/' },
  'E': { name: 'ProjectEuler', url: 'https://projecteuler.net/' },
  'L': { name: 'LibGen', url: 'https://libgen.li' },
  'c': { name: 'Twitch Cooller', url: 'https://twitch.tv/cooller' },
  'g': { name: 'Gmail', url: 'https://gmail.com' },
  'h': { name: 'SciHub', url: 'https://sci-hub.hkvisa.net/' },
  'k': { name: 'Reddit MechKeys', url: 'https://reddit.com/r/MechanicalKeyboards/' },
  'l': { name: 'LastFM', url: 'https://last.fm/user/e7z0x1' },
  's': { name: 'Steam Store', url: 'https://store.steampowered.com' },
  'u': { name: 'Reddit UnixPorn', url: 'https://reddit.com/r/unixporn' },
  'v': { name: 'VK', url: 'https://vk.com' },
  'y': { name: 'YouTube', url: 'https://youtube.com/' },
  'z': { name: 'Z-Lib', url: 'https://z-lib.is' }
};

Object.entries(quickmarks).forEach(([key, site]) => {
  // Current tab (prefix 'o')
  api.mapkey('o' + key, 'Open ' + site.name, () => {
    location.href = site.url;
  });
  // New tab (prefix 'gn' for "Go New")
  api.mapkey('gn' + key, 'Open ' + site.name + ' in new tab', () => {
    api.tabOpenLink(site.url);
  });
});

// ========== Site-specific ==========
// Disable Surfingkeys on certain sites
settings.blocklistPattern = /mail\.google\.com|docs\.google\.com|discord\.com/i;

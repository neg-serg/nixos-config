// Surfingkeys configuration
// https://github.com/brookhong/Surfingkeys

// ========== Settings ==========
settings.hintAlign = "left";
settings.hintCharacters = "asdfghjkl";
settings.omnibarSuggestion = true;
settings.omnibarPosition = "bottom";
settings.focusFirstCandidate = false;
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

/* Global Reset */
.sk_theme {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  background: var(--bg);
  color: var(--fg);
}

.sk_theme tbody {
  color: var(--fg);
}

.sk_theme input {
  color: var(--fg);
}

/* Omnibar */
#sk_omnibar {
  width: 85%;
  left: 7.5%;
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
  border: none !important;
  box-shadow: none !important;
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
  max-height: calc(12 * 1.5em);
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
  border-bottom: 1px solid transparent;
}

#sk_omnibarSearchResult li:nth-child(odd) {
  background: var(--bg) !important;
}

#sk_omnibarSearchResult li.focused {
  background: var(--bg-highlight) !important;
}

#sk_omnibarSearchResult li .title {
  color: var(--fg) !important;
  font-weight: 600 !important;
}

#sk_omnibarSearchResult li .url {
  color: var(--fg-muted) !important;
  font-size: var(--font-size) !important;
  margin-left: 8px;
}

/* Omnibar Metadata (Source, Timestamp) */
#sk_omnibarSearchResult li .source {
  color: var(--accent) !important;
  font-weight: bold;
  margin-right: 8px;
}

#sk_omnibar p {
  margin-bottom: 0px !important;
}

/* Status bar / Banner */
#sk_banner {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
  background: var(--bg) !important;
  color: var(--fg) !important;
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
  padding: 6px !important;
  color: var(--fg) !important;
}

#sk_keystroke kbd {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
  color: var(--accent) !important;
  background: var(--hint-bg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0;
  padding: 2px 4px;
  margin: 2px;
  box-shadow: none;
}

#sk_keystroke .annotation {
  color: var(--fg) !important;
}

#sk_keystroke .candidates {
  color: var(--accent) !important;
}

/* Status line */
#sk_status {
  font-family: var(--font-mono);
  font-size: var(--font-size);
  font-weight: 600;
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
  border-radius: 0;
}

#sk_status > span {
  padding: 4px 8px;
  color: var(--fg) !important;
  border-right: 1px solid var(--border);
}

/* Search Matches on Page */
.sk_find_highlight {
  background: var(--bg-highlight) !important;
  color: var(--fg) !important;
  border-bottom: 2px solid var(--accent) !important;
}

/* Omnibar match highlight */
#sk_omnibar span.omnibar_highlight {
  color: var(--accent) !important;
  text-shadow: none !important;
}

/* Search Bar (Visual Mode /) */
#sk_find {
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
  color: var(--fg) !important;
}

#sk_find input {
  font-family: var(--font-mono) !important;
  font-weight: 600 !important;
  color: var(--fg) !important;
  background: transparent !important; 
  border: none !important;
}

/* Tab switcher */
#sk_tabs {
  background: var(--bg) !important;
  border: 1px solid var(--border) !important;
}

#sk_tabs div.sk_tab {
  background: var(--bg) !important;
  border-bottom: 1px solid var(--border) !important;
}

#sk_tabs div.sk_tab_hint {
  background: var(--hint-bg) !important;
  color: var(--accent) !important;
  border: 1px solid var(--border) !important;
}

#sk_tabs div.sk_tab_title {
  color: var(--fg) !important;
}

#sk_tabs div.sk_tab_url {
  color: var(--fg-muted) !important;
}

/* Markdown/Misc Popups */
#sk_bubble {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}

#sk_usage {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}

#sk_usage .feature_name {
  color: var(--accent) !important;
  border-bottom: 2px solid var(--border) !important;
}

#sk_usage .feature_name > span {
  border-bottom: none !important;
}

#sk_popup {
  background: var(--bg) !important;
  color: var(--fg) !important;
  border: 1px solid var(--border) !important;
}
`;
// ========== Hints Styling (Shadow DOM) ==========
// Hints live in a separate Shadow DOM and DON'T inherit settings.theme!
// Must use api.Hints.style() API to override the default yellow gradient.
// We start with "div" to prevent the default wrapper which would break "mask" selector
api.Hints.style(`
  div, mask {
    font-family: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace !important;
    font-size: 0.875rem !important;
    font-weight: 600 !important;
    padding: 2px 4px !important;
    background: #001742 !important;
    background-image: none !important;
    color: #89cdd2 !important;
    border: 1px solid #0a3749 !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }
  
  mask {
    background: rgba(137, 205, 210, 0.3) !important;
    border: 1px solid #89cdd2 !important;
  }

  mask.activeInput {
    background: rgba(137, 205, 210, 0.6) !important;
    border: 2px solid #89cdd2 !important;
  }
`);

// Style for text/visual mode hints
api.Hints.style(`
  div {
    font-family: "Iosevka", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace !important;
    font-size: 0.875rem !important;
    font-weight: 600 !important;
    padding: 2px 4px !important;
    background: #001742 !important;
    background-image: none !important;
    color: #89cdd2 !important;
    border: 1px solid #0a3749 !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }
  div.begin {
    color: #89cdd2 !important;
  }
`, "text");

// ========== Smart Omnibar ==========
// Unmap default bindings first to avoid conflicts
api.unmap('t');

api.unmap('O');
api.unmap('b');
api.unmap('v');

// Smart navigation: opens omnibar for URL/Search input
api.mapkey("t", "Open URL/Search (New Tab)", () => {
  api.Front.openOmnibar({ type: "URLs" });
});



api.mapkey("O", "Open URL/Search (New Tab)", () => {
  api.Front.openOmnibar({ type: "URLs" });
});

api.mapkey("U", "Open Recently Closed Tabs", () => {
  api.Front.openOmnibar({ type: "URLs", extra: "getRecentlyClosed" });
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
api.map('E', 'gT');  // Previous tab
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

// Force all inputs to be URLs by default (pass-through)
settings.defaultSearchEngine = 'g';

// Smart Enter: No spaces -> URL, Spaces -> Search
// Smart Enter: No spaces -> URL, Spaces -> Search
api.cunmap('<Enter>');

const customEnterHandler = function () {
  try {
    // Helper to find elements inside Shadow DOM or standard DOM
    const getSkElement = (selector) => {
      const skFrame = document.querySelector('#sk_frame');
      if (skFrame && skFrame.contentDocument) {
        return skFrame.contentDocument.querySelector(selector);
      }
      return document.querySelector(selector) ||
        (document.body.shadowRoot && document.body.shadowRoot.querySelector(selector));
    };

    const input = getSkElement('#sk_omnibarSearchArea input');
    if (!input) {
      api.Front.showBanner("DEBUG: Input Not Found! Fallback...");
      return true;
    }

    const text = input.value.trim();
    const focused = getSkElement('#sk_omnibarSearchResult li.focused');

    let isFirstOrNone = true;
    if (focused && focused.parentElement) {
      const children = Array.from(focused.parentElement.children);
      const index = children.indexOf(focused);
      if (index > 0) isFirstOrNone = false;
    }

    // If user selected a specific item (not the first one/input), click it
    if (!isFirstOrNone && focused) {
      focused.click();
      return;
    }

    if (text.length === 0) return;

    /* 
       Logic:
       1. Check for Multi-Engine Flags (-y, -g, etc.) -> Search
       2. No Flags + Spaces -> Search (Google)
       3. No Flags + No Spaces -> URL
    */

    let searchUrl = null;
    let query = text;
    let engineName = "";

    if (text.endsWith(' -y')) {
      searchUrl = 'https://www.youtube.com/results?search_query=';
      query = text.slice(0, -3);
      engineName = "YouTube";
    } else if (text.endsWith(' -w')) {
      searchUrl = 'https://en.wikipedia.org/wiki/Special:Search?search=';
      query = text.slice(0, -3);
      engineName = "Wikipedia";
    } else if (text.endsWith(' -gh')) {
      searchUrl = 'https://github.com/search?q=';
      query = text.slice(0, -4);
      engineName = "GitHub";
    } else if (text.endsWith(' -d')) {
      searchUrl = 'https://duckduckgo.com/?q=';
      query = text.slice(0, -3);
      engineName = "DuckDuckGo";
    } else if (text.endsWith(' -npm')) {
      searchUrl = 'https://www.npmjs.com/search?q=';
      query = text.slice(0, -5);
      engineName = "NPM";
    } else if (text.endsWith(' -g')) {
      searchUrl = 'https://www.google.com/search?q=';
      query = text.slice(0, -3);
      engineName = "Google";
    } else if (/\s/.test(input.value)) {
      // No flags, but has spaces (even padded) -> Default Search
      searchUrl = 'https://www.google.com/search?q=';
      engineName = "Google";
    }

    if (searchUrl) {
      api.Front.showBanner(`DEBUG: Search ${engineName}: ${query}`);
      api.tabOpenLink(searchUrl + encodeURIComponent(query));
      api.Front.closeOmnibar();
    } else {
      // Default: Treat as URL
      let url = text;
      // If no protocol, prepend http://
      if (!/^[a-zA-Z]+:\/\//.test(text)) {
        url = 'http://' + url;
      }

      api.Front.showBanner("DEBUG: Opening URL: " + url);
      api.tabOpenLink(url);
      api.Front.closeOmnibar();
    }
  } catch (e) {
    api.Front.showBanner("DEBUG ERROR: " + e.message);
    console.error(e);
  }
};

api.cmap('<Enter>', customEnterHandler);
api.cmap('<Ctrl-Enter>', customEnterHandler);

api.Front.showBanner("SurfingKeys Config Loaded (DEBUG Mode)");

// ========== Omnibar Hotkeys ==========
// Ctrl+Alt+G: Convert current input to Google search
api.cmap('<Ctrl-Alt-g>', function () {
  const input = document.querySelector('#sk_omnibarSearchArea input');
  if (input && input.value) {
    const query = input.value;
    api.Front.openOmnibar({ type: 'SearchEngine', extra: 'g', pref: query });
  }
});

// Ctrl+Alt+D: Convert current input to DuckDuckGo search
api.cmap('<Ctrl-Alt-d>', function () {
  const input = document.querySelector('#sk_omnibarSearchArea input');
  if (input && input.value) {
    const query = input.value;
    api.Front.openOmnibar({ type: 'SearchEngine', extra: 'd', pref: query });
  }
});

// Ctrl+Alt+Y: Convert current input to YouTube search
api.cmap('<Ctrl-Alt-y>', function () {
  const input = document.querySelector('#sk_omnibarSearchArea input');
  if (input && input.value) {
    const query = input.value;
    api.Front.openOmnibar({ type: 'SearchEngine', extra: 'y', pref: query });
  }
});

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
